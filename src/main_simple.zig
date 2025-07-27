const std = @import("std");
const MinifyingParser = @import("minifier/mod.zig").MinifyingParser;
const parallel = @import("parallel/mod.zig");
const ParallelMinifier = parallel.ParallelMinifier;

const version = "1.0.0";

const Config = struct {
    input_file: ?[]const u8 = null,
    output_file: ?[]const u8 = null,
    pretty: bool = false,
    indent_size: u8 = 2,
    help: bool = false,
    version: bool = false,
    quiet: bool = false,
    stats: bool = false,
    threads: ?usize = null,
    parallel: bool = true,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config = try parseArgs(allocator, args);

    if (config.help) {
        printHelp();
        return;
    }

    if (config.version) {
        printVersion();
        return;
    }

    // Set up input reader
    var input_reader: std.io.AnyReader = undefined;
    var input_file: ?std.fs.File = null;
    defer if (input_file) |f| f.close();

    if (config.input_file) |path| {
        input_file = try std.fs.cwd().openFile(path, .{});
        input_reader = input_file.?.reader().any();
    } else {
        input_reader = std.io.getStdIn().reader().any();
    }

    // Set up output writer
    var output_writer: std.io.AnyWriter = undefined;
    var output_file: ?std.fs.File = null;
    defer if (output_file) |f| f.close();

    if (config.output_file) |path| {
        output_file = try std.fs.cwd().createFile(path, .{});
        output_writer = output_file.?.writer().any();
    } else {
        output_writer = std.io.getStdOut().writer().any();
    }

    // Process JSON
    const start_time = std.time.nanoTimestamp();
    const stats = try processJson(allocator, input_reader, output_writer, config);
    const end_time = std.time.nanoTimestamp();

    if (config.stats and !config.quiet) {
        printStats(stats, end_time - start_time, config);
    }

    if (!config.quiet) {
        const stderr = std.io.getStdErr().writer();
        if (config.input_file != null and config.output_file != null) {
            try stderr.print("✓ Minified {s} -> {s}\n", .{ config.input_file.?, config.output_file.? });
        } else if (config.input_file != null) {
            try stderr.print("✓ Minified {s}\n", .{config.input_file.?});
        } else if (config.output_file != null) {
            try stderr.print("✓ Minified stdin -> {s}\n", .{config.output_file.?});
        }
    }
}

const ProcessStats = struct {
    bytes_read: u64 = 0,
    bytes_written: u64 = 0,
    compression_ratio: f64 = 0.0,
};

fn processJson(allocator: std.mem.Allocator, reader: std.io.AnyReader, writer: std.io.AnyWriter, config: Config) !ProcessStats {
    var stats = ProcessStats{};

    // For large files with parallel enabled and not pretty printing, use parallel processing
    const use_parallel = config.parallel and !config.pretty;

    if (use_parallel) {
        // Read all data first for parallel processing
        var data = std.ArrayList(u8).init(allocator);
        defer data.deinit();

        const buffer_size = 64 * 1024;
        var buffer = try allocator.alloc(u8, buffer_size);
        defer allocator.free(buffer);

        while (true) {
            const bytes_read = try reader.read(buffer);
            if (bytes_read == 0) break;
            try data.appendSlice(buffer[0..bytes_read]);
        }

        stats.bytes_read = data.items.len;

        // Only use parallel for files > 1MB
        if (data.items.len > 1024 * 1024) {
            const parallel_config = ParallelMinifier.Config{
                .buffer_size = 256 * 1024,
                .enable_pipeline = true,
            };

            var minifier = try ParallelMinifier.create(allocator, writer, parallel_config);
            defer minifier.destroy();

            try minifier.process(data.items);
            try minifier.flush();

            stats.bytes_written = data.items.len; // Approximate
        } else {
            // Fall back to single-threaded for small files
            var parser = try MinifyingParser.init(allocator, writer);
            defer parser.deinit(allocator);

            try parser.feed(data.items);
            try parser.flush();

            stats.bytes_written = parser.bytes_processed;
        }
    } else {
        // Single-threaded processing (for pretty printing or when disabled)
        var parser = if (config.pretty)
            try MinifyingParser.initPretty(allocator, writer, config.indent_size)
        else
            try MinifyingParser.init(allocator, writer);
        defer parser.deinit(allocator);

        // Read and process in chunks for streaming
        const buffer_size = 64 * 1024; // 64KB chunks
        var buffer = try allocator.alloc(u8, buffer_size);
        defer allocator.free(buffer);

        while (true) {
            const bytes_read = try reader.read(buffer);
            if (bytes_read == 0) break;

            stats.bytes_read += bytes_read;

            // Feed to parser
            try parser.feed(buffer[0..bytes_read]);
        }

        // Flush any remaining output
        try parser.flush();

        stats.bytes_written = parser.bytes_processed;
    }

    // Calculate stats
    if (stats.bytes_read > 0) {
        stats.compression_ratio = @as(f64, @floatFromInt(stats.bytes_read - stats.bytes_written)) / @as(f64, @floatFromInt(stats.bytes_read)) * 100.0;
    }

    return stats;
}

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !Config {
    _ = allocator;
    var config = Config{};

    var i: usize = 1; // Skip program name
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            config.help = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            config.version = true;
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--pretty")) {
            config.pretty = true;
        } else if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) {
            config.quiet = true;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--stats")) {
            config.stats = true;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--threads")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --threads requires a value\n", .{});
                std.process.exit(1);
            }
            config.threads = try std.fmt.parseInt(usize, args[i], 10);
            if (config.threads.? == 0) {
                std.debug.print("Error: thread count must be greater than 0\n", .{});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--single-threaded")) {
            config.parallel = false;
            config.threads = 1;
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--indent")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --indent requires a value\n", .{});
                std.process.exit(1);
            }
            config.indent_size = try std.fmt.parseInt(u8, args[i], 10);
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --output requires a file path\n", .{});
                std.process.exit(1);
            }
            config.output_file = args[i];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown option: {s}\n", .{arg});
            std.process.exit(1);
        } else {
            // Input file
            if (config.input_file == null) {
                config.input_file = arg;
            } else {
                std.debug.print("Error: Multiple input files specified\n", .{});
                std.process.exit(1);
            }
        }
    }

    return config;
}

fn printHelp() void {
    std.debug.print(
        \\zmin - High-performance JSON minifier v{s}
        \\
        \\USAGE:
        \\    zmin [OPTIONS] [FILE]
        \\
        \\ARGS:
        \\    <FILE>    Input JSON file (stdin if not specified)
        \\
        \\OPTIONS:
        \\    -h, --help           Show this help message
        \\    -v, --version        Show version information
        \\    -o, --output         Output file (stdout if not specified)
        \\    -p, --pretty         Pretty print with indentation
        \\    -i, --indent         Indent size for pretty printing (default: 2)
        \\    -q, --quiet          Suppress status messages
        \\    -s, --stats          Show processing statistics
        \\    -t, --threads        Number of threads for parallel processing
        \\    --single-threaded    Force single-threaded mode
        \\
        \\EXAMPLES:
        \\    # Minify a file
        \\    zmin input.json -o output.json
        \\
        \\    # Pretty print from stdin
        \\    cat data.json | zmin --pretty
        \\
        \\    # Show statistics
        \\    zmin large.json --stats -o small.json
        \\
        \\    # Pretty print with 4 spaces
        \\    zmin --pretty --indent 4 input.json
        \\
        \\    # Use 8 threads for parallel processing
        \\    zmin --threads 8 large.json -o output.json
        \\
        \\    # Force single-threaded mode
        \\    zmin --single-threaded input.json
        \\
    , .{version});
}

fn printVersion() void {
    std.debug.print("zmin {s}\n", .{version});
}

fn printStats(stats: ProcessStats, elapsed_ns: i128, config: Config) void {
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const throughput_mbps = if (elapsed_ms > 0)
        (@as(f64, @floatFromInt(stats.bytes_read)) / 1024.0 / 1024.0) / (elapsed_ms / 1000.0)
    else
        0.0;

    std.debug.print("\n📊 Processing Statistics:\n", .{});
    std.debug.print("────────────────────────────────────────\n", .{});
    std.debug.print("  Input size:    {} bytes\n", .{stats.bytes_read});
    std.debug.print("  Output size:   {} bytes\n", .{stats.bytes_written});
    std.debug.print("  Compression:   {d:.1}%\n", .{stats.compression_ratio});
    std.debug.print("  Time:          {d:.2} ms\n", .{elapsed_ms});
    std.debug.print("  Throughput:    {d:.2} MB/s\n", .{throughput_mbps});
    if (config.parallel and stats.bytes_read > 1024 * 1024) {
        const thread_count = config.threads orelse std.Thread.getCpuCount() catch 1;
        std.debug.print("  Mode:          parallel ({} threads)\n", .{thread_count});
    } else {
        std.debug.print("  Mode:          single-threaded\n", .{});
    }
    std.debug.print("────────────────────────────────────────\n", .{});
}
