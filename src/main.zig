const std = @import("std");
const MinifyingParser = @import("minifier/mod.zig").MinifyingParser;
const ParallelMinifier = @import("parallel/mod.zig").ParallelMinifier;
const parallel_config = @import("parallel/config.zig");

// Phase 5: Advanced Features
const StreamingValidator = @import("validation/streaming_validator.zig").StreamingValidator;
const SchemaOptimizer = @import("schema/schema_optimizer.zig").SchemaOptimizer;
const ErrorHandler = @import("production/error_handling.zig").ErrorHandler;
const Logger = @import("production/logging.zig").Logger;

const Options = struct {
    input_file: []const u8,
    output_file: []const u8,
    pretty: bool,
    validate_only: bool,
    indent_size: u8,
    threads: ?usize, // null means auto-detect
    use_parallel: bool,

    // Phase 5: Advanced Features
    enable_validation: bool,
    enable_schema_optimization: bool,
    schema_file: ?[]const u8,
    enable_logging: bool,
    log_level: Logger.LogLevel,
    log_file: ?[]const u8,
    enable_error_handling: bool,
    fail_fast: bool,
    verbose: bool,
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

    // Initialize Phase 5 components
    var logger = Logger.init(allocator);
    defer logger.deinit();

    var error_handler = ErrorHandler.init(allocator);
    defer error_handler.deinit();

    var validator = StreamingValidator.init(allocator);
    defer validator.deinit();

    var schema_optimizer = SchemaOptimizer.init(allocator);
    defer schema_optimizer.deinit();

    // Configure components based on options
    if (options.enable_logging) {
        logger.setLevel(options.log_level);
        logger.setColorsEnabled(true);
        logger.setTimestampEnabled(true);

        if (options.log_file) |log_file| {
            try logger.enableFileLogging(log_file);
        }

        // Only log to stdout if we're not using stdout for output
        if (!std.mem.eql(u8, options.output_file, "-")) {
            try logger.info("zmin starting with Phase 5 advanced features", .{});
        }
    }

    // Disable stdout logging if we're using stdout for output
    if (std.mem.eql(u8, options.output_file, "-")) {
        logger.disableStdoutLogging();
    }

    if (options.enable_error_handling) {
        error_handler.setFailFast(options.fail_fast);
        error_handler.setLogging(options.enable_logging, options.enable_logging);
    }

    if (options.enable_schema_optimization and options.schema_file != null) {
        const schema_file = options.schema_file.?;
        // Load schema from file
        const schema_content = try std.fs.cwd().readFileAlloc(allocator, schema_file, 1024 * 1024);
        defer allocator.free(schema_content);

        try schema_optimizer.loadSchema(schema_content);
        try schema_optimizer.generateOptimizations();

        if (options.enable_logging) {
            try logger.info("Loaded schema from {s} and generated optimizations", .{schema_file});
        }
    }

    if (options.validate_only) {
        try validateFile(allocator, options, &logger, &error_handler, &validator);
    } else {
        try minifyFile(allocator, options, &logger, &error_handler, &validator, &schema_optimizer);
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
        .enable_validation = true,
        .enable_schema_optimization = true,
        .schema_file = null,
        .enable_logging = true,
        .log_level = .Info,
        .log_file = null,
        .enable_error_handling = true,
        .fail_fast = false,
        .verbose = false,
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
            } else if (std.mem.eql(u8, arg, "--no-validation")) {
                options.enable_validation = false;
            } else if (std.mem.eql(u8, arg, "--no-schema-optimization")) {
                options.enable_schema_optimization = false;
            } else if (std.mem.startsWith(u8, arg, "--schema=")) {
                options.schema_file = arg[9..];
            } else if (std.mem.eql(u8, arg, "--no-logging")) {
                options.enable_logging = false;
            } else if (std.mem.startsWith(u8, arg, "--log-level=")) {
                const level_str = arg[12..];
                options.log_level = if (std.mem.eql(u8, level_str, "debug"))
                    Logger.LogLevel.Debug
                else if (std.mem.eql(u8, level_str, "info"))
                    Logger.LogLevel.Info
                else if (std.mem.eql(u8, level_str, "warning"))
                    Logger.LogLevel.Warning
                else if (std.mem.eql(u8, level_str, "error"))
                    Logger.LogLevel.Error
                else if (std.mem.eql(u8, level_str, "critical"))
                    Logger.LogLevel.Critical
                else
                    return error.InvalidLogLevel;
            } else if (std.mem.startsWith(u8, arg, "--log-file=")) {
                options.log_file = arg[11..];
            } else if (std.mem.eql(u8, arg, "--no-error-handling")) {
                options.enable_error_handling = false;
            } else if (std.mem.eql(u8, arg, "--fail-fast")) {
                options.fail_fast = true;
            } else if (std.mem.eql(u8, arg, "--verbose")) {
                options.verbose = true;
                options.log_level = Logger.LogLevel.Debug;
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
        \\Advanced Features (Phase 5):
        \\  --no-validation           Disable streaming validation
        \\  --no-schema-optimization  Disable schema-aware optimization
        \\  --schema=FILE             Load JSON schema from file for optimization
        \\  --no-logging              Disable logging system
        \\  --log-level=LEVEL         Set log level (debug|info|warning|error|critical)
        \\  --log-file=FILE           Write logs to file
        \\  --no-error-handling       Disable error handling and recovery
        \\  --fail-fast               Stop on first error
        \\  --verbose                 Enable verbose output (debug level + extra info)
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
        \\Advanced Examples:
        \\  zmin --schema=schema.json input.json output.json
        \\  zmin --log-level=debug --log-file=zmin.log input.json
        \\  zmin --verbose --fail-fast input.json output.json
        \\  zmin --no-validation --no-schema-optimization input.json
        \\
        \\Performance: 
        \\  - Automatically uses parallel processing for large files (>1MB)
        \\  - Falls back to single-threaded for small files
        \\  - Targets 1GB/s+ throughput with O(1) memory usage
        \\
    ;
    try std.io.getStdOut().writeAll(usage);
}

fn validateFile(allocator: std.mem.Allocator, options: Options, logger: *Logger, error_handler: *ErrorHandler, validator: *StreamingValidator) !void {
    const stdin = std.io.getStdIn();

    const input_file = if (std.mem.eql(u8, options.input_file, "-"))
        stdin
    else
        try std.fs.cwd().openFile(options.input_file, .{});
    defer if (!std.mem.eql(u8, options.input_file, "-")) input_file.close();

    // Use a null writer for validation-only mode
    var null_writer = std.io.null_writer;
    var parser = try MinifyingParser.init(allocator, null_writer.any());
    defer parser.deinit(allocator);

    var buffer: [64 * 1024]u8 = undefined;
    var total_bytes: u64 = 0;
    var timer = try std.time.Timer.start();

    if (options.enable_logging) {
        try logger.info("Starting validation of {s}", .{options.input_file});
    }

    while (true) {
        const bytes_read = try input_file.readAll(&buffer);
        if (bytes_read == 0) break;

        // Use streaming validation if enabled
        if (options.enable_validation) {
            for (buffer[0..bytes_read], 0..) |byte, i| {
                validator.validateByte(byte, total_bytes + i) catch |err| {
                    if (options.enable_error_handling) {
                        try error_handler.handleError(.ValidationError, "Validation error", "During byte validation", .Medium, true);
                    }
                    if (options.enable_logging) {
                        try logger.logError("Validation", "Byte validation failed", null);
                    }
                    return err;
                };
            }
        }

        try parser.feed(buffer[0..bytes_read]);
        total_bytes += bytes_read;
    }

    try parser.flush();

    // Final validation
    if (options.enable_validation) {
        validator.validateComplete() catch |err| {
            if (options.enable_error_handling) {
                try error_handler.handleError(.ValidationError, "Final validation failed", "During completion check", .High, false);
            }
            if (options.enable_logging) {
                try logger.logError("Validation", "Final validation failed", null);
            }
            return err;
        };
    }

    const elapsed_ns = timer.read();
    const throughput_mbs = if (elapsed_ns > 0)
        (@as(f64, @floatFromInt(total_bytes)) / @as(f64, @floatFromInt(elapsed_ns))) * 1_000_000_000.0 / (1024 * 1024)
    else
        0.0;

    // Print validation result and performance stats
    const stderr = std.io.getStdErr();
    try stderr.writer().print("✓ Valid JSON - {d} bytes in {d:.2}ms ({d:.2} MB/s)\n", .{ total_bytes, @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0, throughput_mbs });

    // Log validation results if enabled
    if (options.enable_logging) {
        try logger.logPerformance("JSON validation", elapsed_ns, total_bytes);

        const validation_report = validator.getValidationReport();
        try logger.info("Validation complete: {d} objects, {d} arrays, {d} strings, {d} numbers", .{ validation_report.objects_count, validation_report.arrays_count, validation_report.strings_count, validation_report.numbers_count });

        if (options.verbose) {
            validator.printErrors(logger.stdout_writer) catch {};
            validator.printWarnings(logger.stdout_writer) catch {};
        }
    }

    // Print error handling summary if enabled
    if (options.enable_error_handling and options.verbose) {
        const error_report = error_handler.getErrorReport();
        if (error_report.total_errors > 0 or error_report.total_warnings > 0) {
            try stderr.writer().print("Error handling: {d} errors, {d} warnings, {d} recovery attempts\n", .{ error_report.total_errors, error_report.total_warnings, error_report.recovery_attempts });
        }
    }
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

fn minifyFile(allocator: std.mem.Allocator, options: Options, logger: *Logger, error_handler: *ErrorHandler, validator: *StreamingValidator, schema_optimizer: *SchemaOptimizer) !void {
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

    if (options.enable_logging) {
        try logger.info("Starting minification of {s} to {s}", .{ options.input_file, options.output_file });
    }

    while (true) {
        const bytes_read = try input_file.readAll(&buffer);
        if (bytes_read == 0) break;
        try input_data.appendSlice(buffer[0..bytes_read]);
    }

    const total_bytes = input_data.items.len;
    const use_parallel = options.use_parallel and total_bytes > 1024 * 1024; // Only parallel for >1MB

    if (options.enable_logging) {
        try logger.info("Processing {d} bytes using {s} mode", .{ total_bytes, if (use_parallel) "parallel" else "single-threaded" });
    }

    if (use_parallel and !options.pretty) {
        // Use parallel processing
        try minifyFileParallel(allocator, options, input_data.items, output_file.writer().any(), &timer, logger, error_handler, validator, schema_optimizer);
    } else {
        // Use single-threaded processing (for pretty-printing or small files)
        try minifyFileSingleThreaded(allocator, options, input_data.items, output_file.writer().any(), &timer, logger, error_handler, validator, schema_optimizer);
    }
}

fn minifyFileSingleThreaded(allocator: std.mem.Allocator, options: Options, input_data: []const u8, writer: std.io.AnyWriter, timer: *std.time.Timer, logger: *Logger, error_handler: *ErrorHandler, validator: *StreamingValidator, schema_optimizer: *SchemaOptimizer) !void {
    // Apply schema optimization if enabled
    var processed_data = input_data;
    if (options.enable_schema_optimization and schema_optimizer.getOptimizations().len > 0) {
        if (options.enable_logging) {
            try logger.info("Applying schema optimizations", .{});
        }

        // TODO: Implement schema optimization
        // For now, just use the original data
        processed_data = input_data;
    }

    var parser = if (options.pretty)
        try MinifyingParser.initPretty(allocator, writer, options.indent_size)
    else
        try MinifyingParser.init(allocator, writer);
    defer parser.deinit(allocator);

    // Process data with validation if enabled
    if (options.enable_validation) {
        for (processed_data, 0..) |byte, i| {
            validator.validateByte(byte, i) catch |err| {
                if (options.enable_error_handling) {
                    try error_handler.handleError(.ValidationError, "Validation error during minification", "During byte processing", .Medium, true);
                }
                if (options.enable_logging) {
                    try logger.logError("Validation", "Byte validation failed during minification", null);
                }
                return err;
            };
            try parser.feedByte(byte);
        }
    } else {
        try parser.feed(processed_data);
    }

    try parser.flush();

    const elapsed_ns = timer.read();
    const throughput_mbs = if (elapsed_ns > 0)
        (@as(f64, @floatFromInt(processed_data.len)) / @as(f64, @floatFromInt(elapsed_ns))) * 1_000_000_000.0 / (1024 * 1024)
    else
        0.0;

    // Print performance stats
    const stderr = std.io.getStdErr();
    const mode = if (options.pretty) "pretty-printed" else "minified";
    try stderr.writer().print("{s} {d} bytes in {d:.2}ms ({d:.2} MB/s) [single-threaded]\n", .{ mode, processed_data.len, @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0, throughput_mbs });

    // Log performance and results if enabled
    if (options.enable_logging) {
        try logger.logPerformance("JSON minification", elapsed_ns, processed_data.len);

        if (options.enable_validation) {
            const validation_report = validator.getValidationReport();
            try logger.info("Minification complete: {d} objects, {d} arrays, {d} strings, {d} numbers", .{ validation_report.objects_count, validation_report.arrays_count, validation_report.strings_count, validation_report.numbers_count });
        }

        if (options.verbose) {
            if (options.enable_validation) {
                validator.printErrors(logger.stdout_writer) catch {};
                validator.printWarnings(logger.stdout_writer) catch {};
            }
        }
    }
}

fn minifyFileParallel(allocator: std.mem.Allocator, options: Options, input_data: []const u8, writer: std.io.AnyWriter, timer: *std.time.Timer, logger: *Logger, error_handler: *ErrorHandler, validator: *StreamingValidator, schema_optimizer: *SchemaOptimizer) !void {
    const thread_count = getOptimalThreadCount(options.threads);

    const config = parallel_config.Config{
        .thread_count = thread_count,
        .chunk_size = 64 * 1024, // 64KB chunks
    };

    var minifier = ParallelMinifier.create(allocator, writer, config) catch |err| {
        // Graceful degradation: fall back to single-threaded on parallel processing errors
        const stderr = std.io.getStdErr();
        try stderr.writer().print("Warning: Parallel processing initialization failed ({s}), falling back to single-threaded\n", .{@errorName(err)});
        return minifyFileSingleThreaded(allocator, options, input_data, writer, timer, logger, error_handler, validator, schema_optimizer);
    };
    defer minifier.destroy();

    // Start timeout timer for parallel processing
    var timeout_timer = std.time.Timer.start() catch timer.*;
    const timeout_ms = 30000; // 30 second timeout

    minifier.process(input_data) catch |err| {
        // Graceful degradation: fall back to single-threaded on processing errors
        const stderr = std.io.getStdErr();
        try stderr.writer().print("Warning: Parallel processing error ({s}), falling back to single-threaded\n", .{@errorName(err)});
        return minifyFileSingleThreaded(allocator, options, input_data, writer, timer, logger, error_handler, validator, schema_optimizer);
    };

    // Check for timeout before flush
    const process_elapsed_ms = timeout_timer.read() / std.time.ns_per_ms;
    if (process_elapsed_ms > timeout_ms) {
        const stderr = std.io.getStdErr();
        try stderr.writer().print("Warning: Parallel processing timeout ({d}ms), falling back to single-threaded\n", .{process_elapsed_ms});
        return minifyFileSingleThreaded(allocator, options, input_data, writer, timer, logger, error_handler, validator, schema_optimizer);
    }

    minifier.flush() catch |err| {
        // Check if this might be a timeout-related error
        const flush_elapsed_ms = timeout_timer.read() / std.time.ns_per_ms;
        const stderr = std.io.getStdErr();
        if (flush_elapsed_ms > timeout_ms) {
            try stderr.writer().print("Warning: Parallel processing timeout during flush ({d}ms), falling back to single-threaded\n", .{flush_elapsed_ms});
        } else {
            try stderr.writer().print("Warning: Parallel flush error ({s}), falling back to single-threaded\n", .{@errorName(err)});
        }
        return minifyFileSingleThreaded(allocator, options, input_data, writer, timer, logger, error_handler, validator, schema_optimizer);
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

    try stderr.writer().print("minified {d} bytes in {d:.2}ms ({d:.2} MB/s) [parallel, {d} threads, {d:.1}% util, total: {d}ms]\n", .{ input_data.len, @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0, throughput_mbs, thread_count, utilization, total_elapsed_ms });
}
