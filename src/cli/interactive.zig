//! Interactive CLI with auto-completion and enhanced UX
//!
//! This module provides an interactive command-line interface with features like
//! auto-completion, syntax highlighting, and command history.

const std = @import("std");
const zmin = @import("zmin_lib");

/// Interactive CLI configuration
pub const InteractiveConfig = struct {
    /// Enable colored output
    use_colors: bool = true,
    /// Enable auto-completion
    auto_complete: bool = true,
    /// History file path
    history_file: []const u8 = ".zmin_history",
    /// Maximum history entries
    max_history: usize = 1000,
    /// Enable syntax highlighting
    syntax_highlight: bool = true,
};

/// Command structure for interactive mode
pub const Command = struct {
    name: []const u8,
    description: []const u8,
    aliases: []const []const u8,
    handler: *const fn (*InteractiveCLI, []const []const u8) anyerror!void,
    min_args: usize = 0,
    max_args: ?usize = null,
    usage: []const u8,
};

/// Interactive CLI instance
pub const InteractiveCLI = struct {
    allocator: std.mem.Allocator,
    config: InteractiveConfig,
    commands: std.StringHashMap(Command),
    history: std.ArrayList([]u8),
    current_mode: zmin.ProcessingMode = .sport,
    last_result: ?[]u8 = null,
    running: bool = true,

    /// Available commands
    const builtin_commands = [_]Command{
        .{
            .name = "minify",
            .description = "Minify JSON input",
            .aliases = &.{ "m", "min" },
            .handler = cmdMinify,
            .min_args = 1,
            .usage = "minify <input-file> [output-file]",
        },
        .{
            .name = "validate",
            .description = "Validate JSON without minifying",
            .aliases = &.{ "v", "val" },
            .handler = cmdValidate,
            .min_args = 1,
            .usage = "validate <input-file>",
        },
        .{
            .name = "mode",
            .description = "Set or show processing mode",
            .aliases = &.{"m"},
            .handler = cmdMode,
            .max_args = 1,
            .usage = "mode [eco|sport|turbo]",
        },
        .{
            .name = "stats",
            .description = "Show statistics for last operation",
            .aliases = &.{"s"},
            .handler = cmdStats,
            .max_args = 0,
            .usage = "stats",
        },
        .{
            .name = "batch",
            .description = "Process multiple files",
            .aliases = &.{"b"},
            .handler = cmdBatch,
            .min_args = 1,
            .usage = "batch <pattern> [output-dir]",
        },
        .{
            .name = "benchmark",
            .description = "Run performance benchmark",
            .aliases = &.{"bench"},
            .handler = cmdBenchmark,
            .min_args = 1,
            .usage = "benchmark <input-file> [iterations]",
        },
        .{
            .name = "clear",
            .description = "Clear the screen",
            .aliases = &.{"cls"},
            .handler = cmdClear,
            .usage = "clear",
        },
        .{
            .name = "history",
            .description = "Show command history",
            .aliases = &.{ "h", "hist" },
            .handler = cmdHistory,
            .usage = "history [n]",
        },
        .{
            .name = "help",
            .description = "Show help information",
            .aliases = &.{ "?", "h" },
            .handler = cmdHelp,
            .usage = "help [command]",
        },
        .{
            .name = "exit",
            .description = "Exit interactive mode",
            .aliases = &.{ "quit", "q" },
            .handler = cmdExit,
            .usage = "exit",
        },
    };

    pub fn init(allocator: std.mem.Allocator, config: InteractiveConfig) !InteractiveCLI {
        var cli = InteractiveCLI{
            .allocator = allocator,
            .config = config,
            .commands = std.StringHashMap(Command).init(allocator),
            .history = std.ArrayList([]u8).init(allocator),
        };

        // Register builtin commands
        for (builtin_commands) |cmd| {
            try cli.commands.put(cmd.name, cmd);
            for (cmd.aliases) |alias| {
                try cli.commands.put(alias, cmd);
            }
        }

        // Load history
        try cli.loadHistory();

        return cli;
    }

    pub fn deinit(self: *InteractiveCLI) void {
        // Save history before exit
        self.saveHistory() catch {};

        // Free history entries
        for (self.history.items) |entry| {
            self.allocator.free(entry);
        }
        self.history.deinit();

        // Free last result
        if (self.last_result) |result| {
            self.allocator.free(result);
        }

        self.commands.deinit();
    }

    /// Run the interactive loop
    pub fn run(self: *InteractiveCLI) !void {
        _ = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn().reader();

        // Print welcome message
        try self.printWelcome();

        var buf: [4096]u8 = undefined;

        while (self.running) {
            // Print prompt
            try self.printPrompt();

            // Read input
            if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |input| {
                const trimmed = std.mem.trim(u8, input, " \t\r\n");
                if (trimmed.len == 0) continue;

                // Add to history
                try self.addToHistory(trimmed);

                // Parse and execute command
                try self.executeCommand(trimmed);
            } else {
                // EOF, exit gracefully
                self.running = false;
            }
        }
    }

    fn printWelcome(self: *InteractiveCLI) !void {
        const stdout = std.io.getStdOut().writer();

        if (self.config.use_colors) {
            try stdout.print("\x1b[1;36m", .{}); // Bold cyan
        }

        try stdout.print(
            \\╔═══════════════════════════════════════╗
            \\║      zmin Interactive Mode v1.0       ║
            \\║   High-Performance JSON Minifier      ║
            \\╚═══════════════════════════════════════╝
            \\
        , .{});

        if (self.config.use_colors) {
            try stdout.print("\x1b[0m", .{}); // Reset
        }

        try stdout.print("Type 'help' for available commands.\n\n", .{});
    }

    fn printPrompt(self: *InteractiveCLI) !void {
        const stdout = std.io.getStdOut().writer();

        if (self.config.use_colors) {
            // Mode color
            const color = switch (self.current_mode) {
                .eco => "\x1b[32m", // Green
                .sport => "\x1b[33m", // Yellow
                .turbo => "\x1b[31m", // Red
            };
            try stdout.print("{s}[{s}]\x1b[0m ", .{ color, @tagName(self.current_mode) });
            try stdout.print("\x1b[1;34mzmin>\x1b[0m ", .{}); // Bold blue
        } else {
            try stdout.print("[{s}] zmin> ", .{@tagName(self.current_mode)});
        }
    }

    fn executeCommand(self: *InteractiveCLI, input: []const u8) !void {
        var iter = std.mem.tokenize(u8, input, " \t");
        const cmd_name = iter.next() orelse return;

        // Collect arguments
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        while (iter.next()) |arg| {
            try args.append(arg);
        }

        // Find and execute command
        if (self.commands.get(cmd_name)) |cmd| {
            // Validate argument count
            if (args.items.len < cmd.min_args) {
                try self.printError("Not enough arguments. Usage: {s}", .{cmd.usage});
                return;
            }

            if (cmd.max_args) |max| {
                if (args.items.len > max) {
                    try self.printError("Too many arguments. Usage: {s}", .{cmd.usage});
                    return;
                }
            }

            // Execute command
            cmd.handler(self, args.items) catch |err| {
                try self.printError("Command failed: {}", .{err});
            };
        } else {
            try self.printError("Unknown command: '{s}'. Type 'help' for available commands.", .{cmd_name});
        }
    }

    fn cmdMinify(self: *InteractiveCLI, args: []const []const u8) !void {
        const stdout = std.io.getStdOut().writer();
        const input_file = args[0];
        const output_file = if (args.len > 1) args[1] else null;

        // Read input file
        const input = std.fs.cwd().readFileAlloc(self.allocator, input_file, 1e9) catch |err| {
            try self.printError("Failed to read file '{s}': {}", .{ input_file, err });
            return;
        };
        defer self.allocator.free(input);

        // Minify
        const start = std.time.microTimestamp();
        const output = zmin.minifyWithMode(self.allocator, input, self.current_mode) catch |err| {
            try self.printError("Minification failed: {}", .{err});
            return;
        };
        const duration = std.time.microTimestamp() - start;

        // Free previous result
        if (self.last_result) |result| {
            self.allocator.free(result);
        }
        self.last_result = output;

        // Write output
        if (output_file) |out_file| {
            std.fs.cwd().writeFile(out_file, output) catch |err| {
                try self.printError("Failed to write file '{s}': {}", .{ out_file, err });
                return;
            };
            try self.printSuccess("Minified to '{s}'", .{out_file});
        } else {
            try stdout.print("{s}\n", .{output});
        }

        // Print stats
        const compression = @as(f32, @floatFromInt(input.len - output.len)) / @as(f32, @floatFromInt(input.len)) * 100;
        const throughput = @as(f32, @floatFromInt(input.len)) / @as(f32, @floatFromInt(duration));

        try self.printInfo("Stats: {d} → {d} bytes ({d:.1}% reduction), {d:.0} MB/s", .{ input.len, output.len, compression, throughput });
    }

    fn cmdValidate(self: *InteractiveCLI, args: []const []const u8) !void {
        const input_file = args[0];

        // Read input file
        const input = std.fs.cwd().readFileAlloc(self.allocator, input_file, 1e9) catch |err| {
            try self.printError("Failed to read file '{s}': {}", .{ input_file, err });
            return;
        };
        defer self.allocator.free(input);

        // Validate
        zmin.validate(input) catch |err| {
            try self.printError("Invalid JSON: {}", .{err});
            return;
        };

        try self.printSuccess("Valid JSON", .{});
    }

    fn cmdMode(self: *InteractiveCLI, args: []const []const u8) !void {
        if (args.len == 0) {
            // Show current mode
            try self.printInfo("Current mode: {s}", .{@tagName(self.current_mode)});
            return;
        }

        // Set mode
        const mode_str = args[0];
        if (std.mem.eql(u8, mode_str, "eco")) {
            self.current_mode = .eco;
        } else if (std.mem.eql(u8, mode_str, "sport")) {
            self.current_mode = .sport;
        } else if (std.mem.eql(u8, mode_str, "turbo")) {
            self.current_mode = .turbo;
        } else {
            try self.printError("Invalid mode: '{s}'. Valid modes: eco, sport, turbo", .{mode_str});
            return;
        }

        try self.printSuccess("Mode set to: {s}", .{@tagName(self.current_mode)});
    }

    fn cmdStats(self: *InteractiveCLI, args: []const []const u8) !void {
        _ = args;

        if (self.last_result == null) {
            try self.printInfo("No previous operation to show stats for", .{});
            return;
        }

        // Show detailed stats
        try self.printInfo("Last operation statistics:", .{});
        try self.printInfo("  Output size: {d} bytes", .{self.last_result.?.len});
        try self.printInfo("  Mode used: {s}", .{@tagName(self.current_mode)});
    }

    fn cmdBatch(self: *InteractiveCLI, args: []const []const u8) !void {
        const pattern = args[0];
        const output_dir = if (args.len > 1) args[1] else "minified";

        // Create output directory
        std.fs.cwd().makeDir(output_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                try self.printError("Failed to create directory '{s}': {}", .{ output_dir, err });
                return;
            },
        };

        // Find files matching the glob pattern
        const matching_files = try self.findMatchingFiles(pattern);
        defer {
            for (matching_files.items) |file_path| {
                self.allocator.free(file_path);
            }
            matching_files.deinit();
        }

        if (matching_files.items.len == 0) {
            try self.printWarning("No files found matching pattern: {s}", .{pattern});
            return;
        }

        try self.printInfo("Found {} files matching pattern: {s}", .{ matching_files.items.len, pattern });
        try self.printInfo("Output directory: {s}", .{output_dir});

        // Process each matching file
        var processed: u32 = 0;
        var failed: u32 = 0;

        for (matching_files.items) |file_path| {
            // Generate output filename
            const base_name = std.fs.path.basename(file_path);
            const name_no_ext = if (std.mem.lastIndexOf(u8, base_name, ".")) |dot_pos|
                base_name[0..dot_pos]
            else
                base_name;

            const output_file = try std.fmt.allocPrint(self.allocator, "{s}/{s}.min.json", .{ output_dir, name_no_ext });
            defer self.allocator.free(output_file);

            // Process the file
            self.processBatchFile(file_path, output_file) catch |err| {
                try self.printError("Failed to process '{s}': {}", .{ file_path, err });
                failed += 1;
                continue;
            };

            processed += 1;
            try self.printInfo("Processed: {s} -> {s}", .{ file_path, output_file });
        }

        try self.printSuccess("Batch processing complete: {} processed, {} failed", .{ processed, failed });
    }

    fn cmdBenchmark(self: *InteractiveCLI, args: []const []const u8) !void {
        const input_file = args[0];
        const iterations = if (args.len > 1) try std.fmt.parseInt(u32, args[1], 10) else 100;

        // Read input file
        const input = std.fs.cwd().readFileAlloc(self.allocator, input_file, 1e9) catch |err| {
            try self.printError("Failed to read file '{s}': {}", .{ input_file, err });
            return;
        };
        defer self.allocator.free(input);

        try self.printInfo("Running benchmark: {d} iterations of {s} mode", .{ iterations, @tagName(self.current_mode) });

        var total_time: u64 = 0;
        var min_time: u64 = std.math.maxInt(u64);
        var max_time: u64 = 0;

        for (0..iterations) |i| {
            const start = std.time.microTimestamp();
            const output = try zmin.minifyWithMode(self.allocator, input, self.current_mode);
            const duration = std.time.microTimestamp() - start;
            self.allocator.free(output);

            total_time += duration;
            min_time = @min(min_time, duration);
            max_time = @max(max_time, duration);

            if ((i + 1) % 10 == 0) {
                try self.printProgress("Progress: {d}/{d}", .{ i + 1, iterations });
            }
        }

        const avg_time = total_time / iterations;
        const throughput = @as(f32, @floatFromInt(input.len)) / @as(f32, @floatFromInt(avg_time));

        try self.printSuccess("\nBenchmark complete!", .{});
        try self.printInfo("  Iterations: {d}", .{iterations});
        try self.printInfo("  Avg time: {d}µs", .{avg_time});
        try self.printInfo("  Min time: {d}µs", .{min_time});
        try self.printInfo("  Max time: {d}µs", .{max_time});
        try self.printInfo("  Throughput: {d:.2} MB/s", .{throughput});
    }

    fn cmdClear(self: *InteractiveCLI, args: []const []const u8) !void {
        _ = self;
        _ = args;
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\x1b[2J\x1b[H", .{}); // Clear screen and move cursor to top
    }

    fn cmdHistory(self: *InteractiveCLI, args: []const []const u8) !void {
        const stdout = std.io.getStdOut().writer();
        const count = if (args.len > 0) try std.fmt.parseInt(usize, args[0], 10) else 20;

        const start = if (self.history.items.len > count) self.history.items.len - count else 0;

        for (self.history.items[start..], start..) |entry, i| {
            try stdout.print("{d: >4}: {s}\n", .{ i + 1, entry });
        }
    }

    fn cmdHelp(self: *InteractiveCLI, args: []const []const u8) !void {
        const stdout = std.io.getStdOut().writer();

        if (args.len > 0) {
            // Show help for specific command
            const cmd_name = args[0];
            if (self.commands.get(cmd_name)) |cmd| {
                try stdout.print("\n{s} - {s}\n", .{ cmd.name, cmd.description });
                try stdout.print("Usage: {s}\n", .{cmd.usage});
                if (cmd.aliases.len > 0) {
                    try stdout.print("Aliases: ", .{});
                    for (cmd.aliases, 0..) |alias, i| {
                        if (i > 0) try stdout.print(", ", .{});
                        try stdout.print("{s}", .{alias});
                    }
                    try stdout.print("\n", .{});
                }
            } else {
                try self.printError("Unknown command: '{s}'", .{cmd_name});
            }
        } else {
            // Show all commands
            try stdout.print("\nAvailable commands:\n\n", .{});

            // Get unique commands (skip aliases)
            var shown = std.StringHashMap(void).init(self.allocator);
            defer shown.deinit();

            for (builtin_commands) |cmd| {
                if (!shown.contains(cmd.name)) {
                    try shown.put(cmd.name, {});
                    try stdout.print("  {s: <12} {s}\n", .{ cmd.name, cmd.description });
                }
            }

            try stdout.print("\nType 'help <command>' for detailed usage.\n", .{});
        }
    }

    fn cmdExit(self: *InteractiveCLI, args: []const []const u8) !void {
        _ = args;
        self.running = false;
        try self.printInfo("Goodbye!", .{});
    }

    fn addToHistory(self: *InteractiveCLI, command: []const u8) !void {
        const entry = try self.allocator.dupe(u8, command);
        try self.history.append(entry);

        // Limit history size
        if (self.history.items.len > self.config.max_history) {
            const old = self.history.orderedRemove(0);
            self.allocator.free(old);
        }
    }

    fn loadHistory(self: *InteractiveCLI) !void {
        const file = std.fs.cwd().openFile(self.config.history_file, .{}) catch {
            // History file doesn't exist, that's ok
            return;
        };
        defer file.close();

        const reader = file.reader();
        var buf: [4096]u8 = undefined;

        while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            const entry = try self.allocator.dupe(u8, line);
            try self.history.append(entry);
        }
    }

    fn saveHistory(self: *InteractiveCLI) !void {
        const file = try std.fs.cwd().createFile(self.config.history_file, .{});
        defer file.close();

        const writer = file.writer();
        for (self.history.items) |entry| {
            try writer.print("{s}\n", .{entry});
        }
    }

    // Print helpers with colors
    fn printError(self: *InteractiveCLI, comptime fmt: []const u8, args: anytype) !void {
        const stdout = std.io.getStdOut().writer();
        if (self.config.use_colors) {
            try stdout.print("\x1b[31m❌ ", .{}); // Red
            try stdout.print(fmt, args);
            try stdout.print("\x1b[0m\n", .{});
        } else {
            try stdout.print("ERROR: ", .{});
            try stdout.print(fmt, args);
            try stdout.print("\n", .{});
        }
    }

    fn printSuccess(self: *InteractiveCLI, comptime fmt: []const u8, args: anytype) !void {
        const stdout = std.io.getStdOut().writer();
        if (self.config.use_colors) {
            try stdout.print("\x1b[32m✅ ", .{}); // Green
            try stdout.print(fmt, args);
            try stdout.print("\x1b[0m\n", .{});
        } else {
            try stdout.print("SUCCESS: ", .{});
            try stdout.print(fmt, args);
            try stdout.print("\n", .{});
        }
    }

    fn printInfo(self: *InteractiveCLI, comptime fmt: []const u8, args: anytype) !void {
        const stdout = std.io.getStdOut().writer();
        if (self.config.use_colors) {
            try stdout.print("\x1b[36mℹ️  ", .{}); // Cyan
            try stdout.print(fmt, args);
            try stdout.print("\x1b[0m\n", .{});
        } else {
            try stdout.print("INFO: ", .{});
            try stdout.print(fmt, args);
            try stdout.print("\n", .{});
        }
    }

    fn printProgress(self: *InteractiveCLI, comptime fmt: []const u8, args: anytype) !void {
        const stdout = std.io.getStdOut().writer();
        if (self.config.use_colors) {
            try stdout.print("\r\x1b[33m⏳ ", .{}); // Yellow
            try stdout.print(fmt, args);
            try stdout.print("\x1b[0m", .{});
        } else {
            try stdout.print("\r", .{});
            try stdout.print(fmt, args);
        }
    }

    /// Find files matching a glob pattern
    fn findMatchingFiles(self: *InteractiveCLI, pattern: []const u8) !std.ArrayList([]u8) {
        var matches = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (matches.items) |path| {
                self.allocator.free(path);
            }
            matches.deinit();
        }

        // Simple glob implementation - supports * and ? wildcards
        const dir_path = std.fs.path.dirname(pattern) orelse ".";
        const file_pattern = std.fs.path.basename(pattern);

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            std.debug.print("Failed to open directory '{s}': {}\n", .{ dir_path, err });
            return matches;
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .file) continue;

            if (try self.matchesGlobPattern(entry.name, file_pattern)) {
                const full_path = if (std.mem.eql(u8, dir_path, "."))
                    try self.allocator.dupe(u8, entry.name)
                else
                    try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });

                try matches.append(full_path);
            }
        }

        return matches;
    }

    /// Check if a filename matches a glob pattern
    fn matchesGlobPattern(self: *InteractiveCLI, filename: []const u8, pattern: []const u8) !bool {
        _ = self;
        return matchGlob(filename, pattern);
    }

    /// Process a single file in batch mode
    fn processBatchFile(self: *InteractiveCLI, input_file: []const u8, output_file: []const u8) !void {
        // Read input file
        const input = std.fs.cwd().readFileAlloc(self.allocator, input_file, 1e9) catch |err| {
            return err;
        };
        defer self.allocator.free(input);

        // Minify using current mode
        const minifier = @import("../minifier/mod.zig");
        const result = try minifier.minifyWithMode(self.allocator, input, self.current_mode);
        defer self.allocator.free(result);

        // Write output file
        const output_file_handle = std.fs.cwd().createFile(output_file, .{}) catch |err| {
            return err;
        };
        defer output_file_handle.close();

        try output_file_handle.writeAll(result);
    }
};

/// Simple glob pattern matching
fn matchGlob(text: []const u8, pattern: []const u8) bool {
    return matchGlobRecursive(text, pattern, 0, 0);
}

fn matchGlobRecursive(text: []const u8, pattern: []const u8, text_idx: usize, pattern_idx: usize) bool {
    // If we've consumed both strings, it's a match
    if (pattern_idx >= pattern.len) {
        return text_idx >= text.len;
    }

    // If we've consumed the text but not the pattern, check if remaining pattern is only *
    if (text_idx >= text.len) {
        for (pattern[pattern_idx..]) |c| {
            if (c != '*') return false;
        }
        return true;
    }

    const pattern_char = pattern[pattern_idx];
    const text_char = text[text_idx];

    switch (pattern_char) {
        '*' => {
            // Try matching zero characters
            if (matchGlobRecursive(text, pattern, text_idx, pattern_idx + 1)) {
                return true;
            }
            // Try matching one or more characters
            return matchGlobRecursive(text, pattern, text_idx + 1, pattern_idx);
        },
        '?' => {
            // ? matches exactly one character
            return matchGlobRecursive(text, pattern, text_idx + 1, pattern_idx + 1);
        },
        else => {
            // Literal character match
            if (pattern_char == text_char) {
                return matchGlobRecursive(text, pattern, text_idx + 1, pattern_idx + 1);
            }
            return false;
        },
    }
}
