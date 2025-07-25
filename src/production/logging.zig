const std = @import("std");

pub const Logger = struct {
    // Log levels
    level: LogLevel,

    // Output destinations
    stdout_writer: std.io.AnyWriter,
    stderr_writer: std.io.AnyWriter,
    file_writer: ?std.fs.File,

    // Performance tracking
    performance_metrics: PerformanceMetrics,

    // Configuration
    enable_timestamps: bool,
    enable_colors: bool,
    enable_file_logging: bool,
    stdout_logging_enabled: bool,
    log_file_path: ?[]const u8,

    // Statistics
    log_count: u64,
    error_count: u64,
    warning_count: u64,
    debug_count: u64,

    allocator: std.mem.Allocator,

    pub const LogLevel = enum {
        Debug,
        Info,
        Warning,
        Error,
        Critical,
    };

    const PerformanceMetrics = struct {
        start_time: i64,
        last_log_time: i64,
        total_logs: u64,
        avg_log_time_ns: u64,
        max_log_time_ns: u64,
        min_log_time_ns: u64,

        pub fn init() PerformanceMetrics {
            const now = @as(i64, @intCast(std.time.nanoTimestamp()));
            return PerformanceMetrics{
                .start_time = now,
                .last_log_time = now,
                .total_logs = 0,
                .avg_log_time_ns = 0,
                .max_log_time_ns = 0,
                .min_log_time_ns = std.math.maxInt(u64),
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator) Logger {
        return Logger{
            .level = .Info,
            .stdout_writer = std.io.getStdOut().writer().any(),
            .stderr_writer = std.io.getStdErr().writer().any(),
            .file_writer = null,
            .performance_metrics = PerformanceMetrics.init(),
            .enable_timestamps = true,
            .enable_colors = true,
            .enable_file_logging = false,
            .stdout_logging_enabled = true,
            .log_file_path = null,
            .log_count = 0,
            .error_count = 0,
            .warning_count = 0,
            .debug_count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Logger) void {
        if (self.file_writer) |*file| {
            file.close();
        }
        if (self.log_file_path) |path| {
            self.allocator.free(path);
        }
    }

    pub fn setLevel(self: *Logger, level: LogLevel) void {
        self.level = level;
    }

    pub fn enableFileLogging(self: *Logger, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        self.file_writer = file;
        self.log_file_path = try self.allocator.dupe(u8, file_path);
        self.enable_file_logging = true;
    }

    pub fn disableFileLogging(self: *Logger) void {
        if (self.file_writer) |*file| {
            file.close();
            self.file_writer = null;
        }
        if (self.log_file_path) |path| {
            self.allocator.free(path);
            self.log_file_path = null;
        }
        self.enable_file_logging = false;
    }

    pub fn setTimestampEnabled(self: *Logger, enabled: bool) void {
        self.enable_timestamps = enabled;
    }

    pub fn setColorsEnabled(self: *Logger, enabled: bool) void {
        self.enable_colors = enabled;
    }

    pub fn disableStdoutLogging(self: *Logger) void {
        self.stdout_logging_enabled = false;
    }

    pub fn debug(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.Debug)) {
            try self.log(.Debug, format, args);
            self.debug_count += 1;
        }
    }

    pub fn info(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.Info)) {
            try self.log(.Info, format, args);
            self.log_count += 1;
        }
    }

    pub fn warning(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.Warning)) {
            try self.log(.Warning, format, args);
            self.warning_count += 1;
        }
    }

    pub fn err(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.Error)) {
            try self.log(.Error, format, args);
            self.error_count += 1;
        }
    }

    pub fn critical(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.Critical)) {
            try self.log(.Critical, format, args);
            self.error_count += 1;
        }
    }

    fn log(self: *Logger, level: LogLevel, comptime format: []const u8, args: anytype) !void {
        const start_time = std.time.nanoTimestamp();

        var buffer: [1024]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buffer);
        var writer = stream.writer();

        // Add timestamp if enabled
        if (self.enable_timestamps) {
            const timestamp = std.time.timestamp();
            try writer.print("[{d}] ", .{timestamp});
        }

        // Add level with color if enabled
        if (self.enable_colors) {
            try writer.print("{s} ", .{self.getLevelStringColored(level)});
        } else {
            try writer.print("[{s}] ", .{@tagName(level)});
        }

        // Add the actual message
        try writer.print(format, args);
        try writer.writeByte('\n');

        const message = stream.getWritten();

        // Write to appropriate destinations
        switch (level) {
            .Error, .Critical => {
                try self.stderr_writer.writeAll(message);
            },
            else => {
                if (self.stdout_logging_enabled) {
                    try self.stdout_writer.writeAll(message);
                }
            },
        }

        // Write to file if enabled
        if (self.enable_file_logging and self.file_writer != null) {
            if (self.file_writer) |*file| {
                try file.writeAll(message);
            }
        }

        // Update performance metrics
        const end_time = @as(i64, @intCast(std.time.nanoTimestamp()));
        const log_time_ns = @as(u64, @intCast(end_time - start_time));

        self.performance_metrics.last_log_time = end_time;
        self.performance_metrics.total_logs += 1;

        // Update min/max/average
        if (log_time_ns > self.performance_metrics.max_log_time_ns) {
            self.performance_metrics.max_log_time_ns = log_time_ns;
        }
        if (log_time_ns < self.performance_metrics.min_log_time_ns) {
            self.performance_metrics.min_log_time_ns = log_time_ns;
        }

        // Update average
        const total_time = self.performance_metrics.avg_log_time_ns * (self.performance_metrics.total_logs - 1) + log_time_ns;
        self.performance_metrics.avg_log_time_ns = total_time / self.performance_metrics.total_logs;
    }

    fn getLevelStringColored(_: *Logger, level: LogLevel) []const u8 {
        return switch (level) {
            .Debug => "\x1b[36m[DEBUG]\x1b[0m", // Cyan
            .Info => "\x1b[32m[INFO]\x1b[0m", // Green
            .Warning => "\x1b[33m[WARN]\x1b[0m", // Yellow
            .Error => "\x1b[31m[ERROR]\x1b[0m", // Red
            .Critical => "\x1b[35m[CRIT]\x1b[0m", // Magenta
        };
    }

    pub fn logPerformance(self: *Logger, operation: []const u8, duration_ns: u64, bytes_processed: ?usize) !void {
        const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

        if (bytes_processed) |bytes| {
            const throughput_mbps = if (duration_ms > 0)
                (@as(f64, @floatFromInt(bytes)) / duration_ms) * 1000.0 / (1024 * 1024)
            else
                0.0;

            try self.info("Performance: {s} took {d:.2} ms, {d:.2} MB/s", .{ operation, duration_ms, throughput_mbps });
        } else {
            try self.info("Performance: {s} took {d:.2} ms", .{ operation, duration_ms });
        }
    }

    pub fn logMemoryUsage(self: *Logger, current_usage: usize, peak_usage: usize) !void {
        const current_mb = @as(f64, @floatFromInt(current_usage)) / (1024 * 1024);
        const peak_mb = @as(f64, @floatFromInt(peak_usage)) / (1024 * 1024);

        try self.info("Memory: Current {d:.2} MB, Peak {d:.2} MB", .{ current_mb, peak_mb });
    }

    pub fn logError(self: *Logger, error_type: []const u8, message: []const u8, context: ?[]const u8) !void {
        if (context) |ctx| {
            try self.err("{s}: {s} (Context: {s})", .{ error_type, message, ctx });
        } else {
            try self.err("{s}: {s}", .{ error_type, message });
        }
    }

    pub fn logWarning(self: *Logger, warning_type: []const u8, message: []const u8, suggestion: ?[]const u8) !void {
        if (suggestion) |sugg| {
            try self.warning("{s}: {s} (Suggestion: {s})", .{ warning_type, message, sugg });
        } else {
            try self.warning("{s}: {s}", .{ warning_type, message });
        }
    }

    pub fn getPerformanceMetrics(self: *Logger) PerformanceMetrics {
        return self.performance_metrics;
    }

    pub fn getLogStatistics(self: *Logger) LogStatistics {
        return LogStatistics{
            .total_logs = self.log_count,
            .error_count = self.error_count,
            .warning_count = self.warning_count,
            .debug_count = self.debug_count,
            .uptime_seconds = @as(u64, @intCast(@divTrunc(std.time.nanoTimestamp() - self.performance_metrics.start_time, 1_000_000_000))),
        };
    }

    pub fn printStatistics(self: *Logger, writer: std.io.AnyWriter) !void {
        const stats = self.getLogStatistics();
        const metrics = self.getPerformanceMetrics();

        try writer.print("Logger Statistics:\n", .{});
        try writer.print("  Total logs: {}\n", .{stats.total_logs});
        try writer.print("  Errors: {}\n", .{stats.error_count});
        try writer.print("  Warnings: {}\n", .{stats.warning_count});
        try writer.print("  Debug: {}\n", .{stats.debug_count});
        try writer.print("  Uptime: {} seconds\n", .{stats.uptime_seconds});
        try writer.print("  Avg log time: {} ns\n", .{metrics.avg_log_time_ns});
        try writer.print("  Min log time: {} ns\n", .{metrics.min_log_time_ns});
        try writer.print("  Max log time: {} ns\n", .{metrics.max_log_time_ns});
    }

    const LogStatistics = struct {
        total_logs: u64,
        error_count: u64,
        warning_count: u64,
        debug_count: u64,
        uptime_seconds: u64,
    };
};
