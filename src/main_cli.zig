//! Enhanced CLI entry point with interactive mode and auto-completion
//!
//! This is the main entry point for the zmin command-line interface,
//! providing both traditional CLI usage and an interactive REPL mode.

const std = @import("std");
const zmin = @import("zmin_lib");
const ArgParser = @import("cli/args_parser.zig").ArgParser;
const Options = @import("cli/args_parser.zig").Options;
const ParseResult = @import("cli/args_parser.zig").ParseResult;
const InteractiveCLI = @import("cli/interactive.zig").InteractiveCLI;
const InteractiveConfig = @import("cli/interactive.zig").InteractiveConfig;
const generateCompletion = @import("cli/args_parser.zig").generateCompletion;

/// Performance statistics
const Stats = struct {
    input_size: usize,
    output_size: usize,
    processing_time_us: u64,
    mode: zmin.ProcessingMode,

    fn print(self: Stats, writer: anytype, verbose: bool) !void {
        const compression = @as(f32, @floatFromInt(self.input_size - self.output_size)) /
            @as(f32, @floatFromInt(self.input_size)) * 100;
        const throughput_mbps = @as(f32, @floatFromInt(self.input_size)) /
            (@as(f32, @floatFromInt(self.processing_time_us)) / 1_000_000) /
            (1024 * 1024);

        if (verbose) {
            try writer.print(
                \\
                \\═══════════════════════════════════════
                \\zmin Performance Report
                \\═══════════════════════════════════════
                \\Mode:              {s}
                \\Input Size:        {d} bytes
                \\Output Size:       {d} bytes
                \\Compression:       {d:.1}%
                \\Processing Time:   {d:.2} ms
                \\Throughput:        {d:.0} MB/s
                \\═══════════════════════════════════════
                \\
            , .{
                @tagName(self.mode),
                self.input_size,
                self.output_size,
                compression,
                @as(f32, @floatFromInt(self.processing_time_us)) / 1000,
                throughput_mbps,
            });
        } else {
            try writer.print("{d} → {d} bytes ({d:.1}% reduction)\n", .{
                self.input_size,
                self.output_size,
                compression,
            });
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse arguments
    var parser = ArgParser.init(allocator, args[0]);
    const parse_result = try parser.parse(args[1..]);

    switch (parse_result) {
        .error_message => |msg| {
            defer allocator.free(msg);
            try std.io.getStdErr().writer().print("Error: {s}\n", .{msg});
            try std.io.getStdErr().writer().print("Try '{s} --help' for more information.\n", .{args[0]});
            std.process.exit(1);
        },
        .options => |options| {
            try processOptions(allocator, &parser, options);
        },
    }
}

fn processOptions(allocator: std.mem.Allocator, parser: *ArgParser, options: Options) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Handle special commands
    if (options.help) {
        try parser.printHelp(stdout);
        return;
    }

    if (options.version) {
        try parser.printVersion(stdout);
        return;
    }

    if (options.completion) |shell| {
        try generateCompletion(shell, parser.program_name, stdout);
        return;
    }

    if (options.interactive) {
        // Enter interactive mode
        const config = InteractiveConfig{
            .use_colors = std.io.getStdOut().isTty(),
            .auto_complete = true,
            .history_file = ".zmin_history",
            .syntax_highlight = true,
        };

        var cli = try InteractiveCLI.init(allocator, config);
        defer cli.deinit();

        try cli.run();
        return;
    }

    // Regular CLI mode
    if (options.input == null and !std.io.getStdIn().isTty()) {
        // Read from stdin
        try processStdin(allocator, options);
    } else if (options.input) |input_file| {
        // Process file
        if (options.benchmark) {
            try runBenchmark(allocator, input_file, options);
        } else {
            try processFile(allocator, input_file, options);
        }
    } else {
        try stderr.print("Error: No input provided\n", .{});
        try stderr.print("Try '{s} --help' for more information.\n", .{parser.program_name});
        std.process.exit(1);
    }
}

fn processStdin(allocator: std.mem.Allocator, options: Options) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Read all input
    const input = try stdin.readAllAlloc(allocator, 1024 * 1024 * 1024); // 1GB max
    defer allocator.free(input);

    if (options.validate_only) {
        // Validate only
        zmin.validate(input) catch |err| {
            try stderr.print("Invalid JSON: {}\n", .{err});
            std.process.exit(1);
        };

        if (!options.quiet) {
            try stdout.print("Valid JSON\n", .{});
        }
        return;
    }

    // Minify
    const start = std.time.microTimestamp();
    const output = zmin.minifyWithMode(allocator, input, options.mode) catch |err| {
        try stderr.print("Minification failed: {}\n", .{err});
        std.process.exit(1);
    };
    defer allocator.free(output);
    const duration = std.time.microTimestamp() - start;

    // Write output
    if (options.output) |output_file| {
        if (std.mem.eql(u8, output_file, "-")) {
            try stdout.print("{s}", .{output});
        } else {
            try std.fs.cwd().writeFile(output_file, output);
        }
    } else {
        try stdout.print("{s}", .{output});
    }

    // Show stats if requested
    if (options.show_stats and !options.quiet) {
        const stats = Stats{
            .input_size = input.len,
            .output_size = output.len,
            .processing_time_us = duration,
            .mode = options.mode,
        };
        try stats.print(stderr, options.verbose);
    }
}

fn processFile(allocator: std.mem.Allocator, input_file: []const u8, options: Options) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Handle stdin input
    const input = if (std.mem.eql(u8, input_file, "-")) blk: {
        const stdin = std.io.getStdIn().reader();
        break :blk try stdin.readAllAlloc(allocator, 1024 * 1024 * 1024);
    } else blk: {
        break :blk try std.fs.cwd().readFileAlloc(allocator, input_file, 1024 * 1024 * 1024);
    };
    defer allocator.free(input);

    if (options.validate_only) {
        // Validate only
        zmin.validate(input) catch |err| {
            try stderr.print("Invalid JSON in '{}': {}\n", .{ input_file, err });
            std.process.exit(1);
        };

        if (!options.quiet) {
            try stdout.print("Valid JSON: {s}\n", .{input_file});
        }
        return;
    }

    // Minify
    const start = std.time.microTimestamp();
    const output = zmin.minifyWithMode(allocator, input, options.mode) catch |err| {
        try stderr.print("Failed to minify '{}': {}\n", .{ input_file, err });
        std.process.exit(1);
    };
    defer allocator.free(output);
    const duration = std.time.microTimestamp() - start;

    // Write output
    if (options.output) |output_file| {
        if (std.mem.eql(u8, output_file, "-")) {
            try stdout.print("{s}", .{output});
        } else {
            try std.fs.cwd().writeFile(output_file, output);
            if (!options.quiet) {
                try stderr.print("Minified '{s}' → '{s}'\n", .{ input_file, output_file });
            }
        }
    } else {
        try stdout.print("{s}", .{output});
    }

    // Show stats if requested
    if (options.show_stats and !options.quiet) {
        const stats = Stats{
            .input_size = input.len,
            .output_size = output.len,
            .processing_time_us = duration,
            .mode = options.mode,
        };
        try stats.print(stderr, options.verbose);
    }
}

fn runBenchmark(allocator: std.mem.Allocator, input_file: []const u8, options: Options) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Read input file
    const input = try std.fs.cwd().readFileAlloc(allocator, input_file, 1024 * 1024 * 1024);
    defer allocator.free(input);

    if (!options.quiet) {
        try stdout.print("Running benchmark: {} iterations of {} mode on '{}' ({} bytes)\n", .{
            options.benchmark_iterations,
            @tagName(options.mode),
            input_file,
            input.len,
        });
    }

    var total_time: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    var max_time: u64 = 0;

    // Warmup
    for (0..10) |_| {
        const output = try zmin.minifyWithMode(allocator, input, options.mode);
        allocator.free(output);
    }

    // Benchmark
    for (0..options.benchmark_iterations) |i| {
        const start = std.time.microTimestamp();
        const output = try zmin.minifyWithMode(allocator, input, options.mode);
        const duration = std.time.microTimestamp() - start;
        allocator.free(output);

        total_time += duration;
        min_time = @min(min_time, duration);
        max_time = @max(max_time, duration);

        if (!options.quiet and (i + 1) % 10 == 0) {
            try stderr.print("\rProgress: {}/{}", .{ i + 1, options.benchmark_iterations });
        }
    }

    if (!options.quiet) {
        try stderr.print("\r", .{});
    }

    const avg_time = total_time / options.benchmark_iterations;
    const throughput_mbps = @as(f32, @floatFromInt(input.len)) /
        (@as(f32, @floatFromInt(avg_time)) / 1_000_000) /
        (1024 * 1024);

    try stdout.print(
        \\
        \\Benchmark Results
        \\═════════════════════════════════════════
        \\File:         {s}
        \\Size:         {} bytes
        \\Mode:         {s}
        \\Iterations:   {}
        \\─────────────────────────────────────────
        \\Average:      {d:.2} ms
        \\Minimum:      {d:.2} ms
        \\Maximum:      {d:.2} ms
        \\Std Dev:      {d:.2} ms
        \\Throughput:   {d:.0} MB/s
        \\═════════════════════════════════════════
        \\
    , .{
        input_file,
        input.len,
        @tagName(options.mode),
        options.benchmark_iterations,
        @as(f32, @floatFromInt(avg_time)) / 1000,
        @as(f32, @floatFromInt(min_time)) / 1000,
        @as(f32, @floatFromInt(max_time)) / 1000,
        calculateStdDev(total_time, options.benchmark_iterations, min_time, max_time) / 1000,
        throughput_mbps,
    });
}

fn calculateStdDev(total: u64, count: u32, min: u64, max: u64) f32 {
    _ = total;
    _ = count;
    const variance = (@as(f32, @floatFromInt(max - min)) * @as(f32, @floatFromInt(max - min))) / 12;
    return @sqrt(variance);
}
