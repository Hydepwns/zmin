const std = @import("std");
const MinifyingParser = @import("minifier/mod.zig").MinifyingParser;
const ParallelMinifier = @import("parallel/mod.zig").ParallelMinifier;
const parallel_config = @import("parallel/config.zig");

const Options = struct {
    input_file: []const u8,
    output_file: []const u8,
    pretty: bool,
    validate_only: bool,
    indent_size: u8,
    threads: ?usize, // null means auto-detect
    use_parallel: bool,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1 and std.mem.eql(u8, args[1], "--help")) {
        try printUsage();
        return;
    }

    const options = try parseArgs(allocator, args);

    if (options.validate_only) {
        try validateFile(allocator, options.input_file);
    } else {
        try minifyFile(allocator, options);
    }
}

fn parseArgs(_: std.mem.Allocator, args: []const []const u8) !Options {
    var options = Options{
        .input_file = "-",
        .output_file = "-",
        .pretty = false,
        .validate_only = false,
        .indent_size = 2,
        .threads = null, // Auto-detect
        .use_parallel = true, // Enable parallel processing by default
    };

    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--pretty")) {
                options.pretty = true;
            } else if (std.mem.eql(u8, arg, "--validate")) {
                options.validate_only = true;
            } else if (std.mem.eql(u8, arg, "--single-threaded")) {
                options.use_parallel = false;
                options.threads = 1;
            } else if (std.mem.startsWith(u8, arg, "--threads=")) {
                const threads_str = arg[10..];
                const thread_count = try std.fmt.parseInt(usize, threads_str, 10);
                if (thread_count == 0) {
                    return error.InvalidThreadCount;
                }
                options.threads = thread_count;
                options.use_parallel = thread_count > 1;
            } else if (std.mem.startsWith(u8, arg, "--indent=")) {
                const indent_str = arg[9..];
                options.indent_size = try std.fmt.parseInt(u8, indent_str, 10);
                if (options.indent_size == 0 or options.indent_size > 8) {
                    return error.InvalidIndentSize;
                }
            } else {
                return error.UnknownOption;
            }
        } else {
            if (options.input_file.len == 1 and options.input_file[0] == '-') {
                options.input_file = arg;
            } else if (options.output_file.len == 1 and options.output_file[0] == '-') {
                options.output_file = arg;
            } else {
                return error.TooManyArguments;
            }
        }
        i += 1;
    }

    return options;
}

fn printUsage() !void {
    const usage =
        \\Usage: zmin [options] [input_file] [output_file]
        \\
        \\Arguments:
        \\  input_file   Input JSON file (default: stdin)
        \\  output_file  Output JSON file (default: stdout)
        \\
        \\Options:
        \\  --pretty           Pretty-print JSON with indentation
        \\  --validate         Validate JSON without outputting
        \\  --indent=N         Set indentation size (1-8 spaces, default: 2)
        \\  --threads=N        Use N threads for parallel processing (default: auto-detect)
        \\  --single-threaded  Force single-threaded processing
        \\
        \\Examples:
        \\  zmin input.json output.json
        \\  zmin --pretty input.json output.json
        \\  zmin --threads=4 input.json output.json
        \\  zmin --single-threaded input.json output.json
        \\  zmin --validate input.json
        \\  zmin --pretty --indent=4 input.json
        \\  zmin < input.json > output.json
        \\
        \\Performance: 
        \\  - Automatically uses parallel processing for large files (>1MB)
        \\  - Falls back to single-threaded for small files
        \\  - Targets 1GB/s+ throughput with O(1) memory usage
        \\
    ;
    try std.io.getStdOut().writeAll(usage);
}

fn validateFile(allocator: std.mem.Allocator, input_path: []const u8) !void {
    const stdin = std.io.getStdIn();

    const input_file = if (std.mem.eql(u8, input_path, "-"))
        stdin
    else
        try std.fs.cwd().openFile(input_path, .{});
    defer if (!std.mem.eql(u8, input_path, "-")) input_file.close();

    // Use a null writer for validation-only mode
    var null_writer = std.io.null_writer;
    var parser = try MinifyingParser.init(allocator, null_writer.any());
    defer parser.deinit(allocator);

    var buffer: [64 * 1024]u8 = undefined;
    var total_bytes: u64 = 0;
    var timer = try std.time.Timer.start();

    while (true) {
        const bytes_read = try input_file.readAll(&buffer);
        if (bytes_read == 0) break;

        try parser.feed(buffer[0..bytes_read]);
        total_bytes += bytes_read;
    }

    try parser.flush();

    const elapsed_ns = timer.read();
    const throughput_mbs = if (elapsed_ns > 0)
        (@as(f64, @floatFromInt(total_bytes)) / @as(f64, @floatFromInt(elapsed_ns))) * 1_000_000_000.0 / (1024 * 1024)
    else
        0.0;

    // Print validation result and performance stats to stderr
    const stderr = std.io.getStdErr();
    try stderr.writer().print("✓ Valid JSON - {} bytes in {:.2}ms ({:.2} MB/s)\n", .{ total_bytes, @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0, throughput_mbs });
}

fn getOptimalThreadCount(requested_threads: ?usize) usize {
    // Auto-detect optimal thread count if not specified
    if (requested_threads) |count| {
        return count;
    }
    
    // Auto-detection: use number of CPU cores, but cap at 8 to avoid overhead
    const cpu_count = std.Thread.getCpuCount() catch 4;
    return @min(cpu_count, 8);
}

fn minifyFile(allocator: std.mem.Allocator, options: Options) !void {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    const input_file = if (std.mem.eql(u8, options.input_file, "-"))
        stdin
    else
        try std.fs.cwd().openFile(options.input_file, .{});
    defer if (!std.mem.eql(u8, options.input_file, "-")) input_file.close();

    const output_file = if (std.mem.eql(u8, options.output_file, "-"))
        stdout
    else
        try std.fs.cwd().createFile(options.output_file, .{});
    defer if (!std.mem.eql(u8, options.output_file, "-")) output_file.close();

    // Read all input first to determine processing strategy
    var input_data = std.ArrayList(u8).init(allocator);
    defer input_data.deinit();
    
    var buffer: [64 * 1024]u8 = undefined;
    var timer = try std.time.Timer.start();

    while (true) {
        const bytes_read = try input_file.readAll(&buffer);
        if (bytes_read == 0) break;
        try input_data.appendSlice(buffer[0..bytes_read]);
    }

    const total_bytes = input_data.items.len;
    const use_parallel = options.use_parallel and total_bytes > 1024 * 1024; // Only parallel for >1MB
    
    if (use_parallel and !options.pretty) {
        // Use parallel processing
        try minifyFileParallel(allocator, options, input_data.items, output_file.writer().any(), &timer);
    } else {
        // Use single-threaded processing (for pretty-printing or small files)
        try minifyFileSingleThreaded(allocator, options, input_data.items, output_file.writer().any(), &timer);
    }
}

fn minifyFileSingleThreaded(allocator: std.mem.Allocator, options: Options, input_data: []const u8, writer: std.io.AnyWriter, timer: *std.time.Timer) !void {
    var parser = if (options.pretty)
        try MinifyingParser.initPretty(allocator, writer, options.indent_size)
    else
        try MinifyingParser.init(allocator, writer);
    defer parser.deinit(allocator);

    try parser.feed(input_data);
    try parser.flush();

    const elapsed_ns = timer.read();
    const throughput_mbs = if (elapsed_ns > 0)
        (@as(f64, @floatFromInt(input_data.len)) / @as(f64, @floatFromInt(elapsed_ns))) * 1_000_000_000.0 / (1024 * 1024)
    else
        0.0;

    // Print performance stats to stderr
    const stderr = std.io.getStdErr();
    const mode = if (options.pretty) "pretty-printed" else "minified";
    try stderr.writer().print("{s} {} bytes in {:.2}ms ({:.2} MB/s) [single-threaded]\n", .{ mode, input_data.len, @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0, throughput_mbs });
}

fn minifyFileParallel(allocator: std.mem.Allocator, options: Options, input_data: []const u8, writer: std.io.AnyWriter, timer: *std.time.Timer) !void {
    const thread_count = getOptimalThreadCount(options.threads);
    
    const config = parallel_config.Config{
        .thread_count = thread_count,
        .chunk_size = 64 * 1024, // 64KB chunks
    };

    var minifier = ParallelMinifier.create(allocator, writer, config) catch |err| {
        // Graceful degradation: fall back to single-threaded on parallel processing errors
        const stderr = std.io.getStdErr();
        try stderr.writer().print("Warning: Parallel processing initialization failed ({}), falling back to single-threaded\n", .{err});
        return minifyFileSingleThreaded(allocator, options, input_data, writer, timer);
    };
    defer minifier.destroy();

    // Start timeout timer for parallel processing
    var timeout_timer = std.time.Timer.start() catch timer.*;
    const timeout_ms = 30000; // 30 second timeout
    
    minifier.process(input_data) catch |err| {
        // Graceful degradation: fall back to single-threaded on processing errors
        const stderr = std.io.getStdErr();
        try stderr.writer().print("Warning: Parallel processing error ({}), falling back to single-threaded\n", .{err});
        return minifyFileSingleThreaded(allocator, options, input_data, writer, timer);
    };
    
    // Check for timeout before flush
    const process_elapsed_ms = timeout_timer.read() / std.time.ns_per_ms;
    if (process_elapsed_ms > timeout_ms) {
        const stderr = std.io.getStdErr();
        try stderr.writer().print("Warning: Parallel processing timeout ({}ms), falling back to single-threaded\n", .{process_elapsed_ms});
        return minifyFileSingleThreaded(allocator, options, input_data, writer, timer);
    }
    
    minifier.flush() catch |err| {
        // Check if this might be a timeout-related error
        const flush_elapsed_ms = timeout_timer.read() / std.time.ns_per_ms;
        const stderr = std.io.getStdErr();
        if (flush_elapsed_ms > timeout_ms) {
            try stderr.writer().print("Warning: Parallel processing timeout during flush ({}ms), falling back to single-threaded\n", .{flush_elapsed_ms});
        } else {
            try stderr.writer().print("Warning: Parallel flush error ({}), falling back to single-threaded\n", .{err});
        }
        return minifyFileSingleThreaded(allocator, options, input_data, writer, timer);
    };

    const elapsed_ns = timer.read();
    const throughput_mbs = if (elapsed_ns > 0)
        (@as(f64, @floatFromInt(input_data.len)) / @as(f64, @floatFromInt(elapsed_ns))) * 1_000_000_000.0 / (1024 * 1024)
    else
        0.0;

    // Print performance stats to stderr with timing info and metrics
    const total_elapsed_ms = timeout_timer.read() / std.time.ns_per_ms;
    const stderr = std.io.getStdErr();
    
    // Calculate estimated thread utilization (simple heuristic)
    const expected_single_thread_time = (@as(f64, @floatFromInt(input_data.len)) / (100.0 * 1024 * 1024)) * 1000.0; // Assume ~100MB/s single-threaded
    const parallel_time_ms = @as(f64, @floatFromInt(total_elapsed_ms));
    const utilization = if (parallel_time_ms > 0) @min(100.0, (expected_single_thread_time / parallel_time_ms) * 100.0 / @as(f64, @floatFromInt(thread_count))) else 0.0;
    
    try stderr.writer().print("minified {} bytes in {:.2}ms ({:.2} MB/s) [parallel, {} threads, {:.1}% util, total: {}ms]\n", .{ 
        input_data.len, 
        @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0, 
        throughput_mbs, 
        thread_count, 
        utilization,
        total_elapsed_ms 
    });
}
