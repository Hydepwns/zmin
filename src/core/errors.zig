//! Structured Error Handling System
//!
//! This module provides a comprehensive error taxonomy, context tracking,
//! and recovery strategies for the zmin JSON minifier.

const std = @import("std");

/// Comprehensive error taxonomy for zmin
pub const ZminError = error{
    // Input/Output errors
    FileNotFound,
    InvalidInputFile,
    OutputWriteError,
    PermissionDenied,
    DiskFull,
    IoTimeout,
    
    // JSON processing errors  
    InvalidJson,
    JsonTooLarge,
    UnexpectedEndOfInput,
    InvalidCharacter,
    InvalidEscapeSequence,
    InvalidUnicode,
    UnterminatedString,
    TrailingComma,
    DuplicateKey,
    DepthLimitExceeded,
    
    // System resource errors
    OutOfMemory,
    InsufficientCores,
    NumaNotAvailable,
    ThreadCreationFailed,
    CpuDetectionFailed,
    
    // Performance errors
    PerformanceThresholdNotMet,
    TimeoutExceeded,
    ThroughputBelowMinimum,
    LatencyAboveMaximum,
    
    // Configuration errors
    InvalidConfiguration,
    UnsupportedMode,
    InvalidChunkSize,
    InvalidThreadCount,
    
    // Strategy-specific errors
    SimdNotSupported,
    StrategyUnavailable,
    FallbackFailed,
};

/// Error severity levels
pub const ErrorSeverity = enum {
    debug,      // Diagnostic information
    info,       // Informational messages
    warning,    // Recoverable issues
    error,      // Errors requiring fallback
    critical,   // Unrecoverable errors
    
    pub fn getColor(self: ErrorSeverity) []const u8 {
        return switch (self) {
            .debug => "\x1b[90m",    // Gray
            .info => "\x1b[36m",     // Cyan
            .warning => "\x1b[33m",  // Yellow
            .error => "\x1b[31m",    // Red
            .critical => "\x1b[91m", // Bright red
        };
    }
    
    pub fn getPrefix(self: ErrorSeverity) []const u8 {
        return switch (self) {
            .debug => "[DEBUG]",
            .info => "[INFO]",
            .warning => "[WARN]",
            .error => "[ERROR]",
            .critical => "[CRITICAL]",
        };
    }
};

/// Error context with rich information
pub const ErrorContext = struct {
    /// The error that occurred
    err: anyerror,
    /// Severity level
    severity: ErrorSeverity,
    /// Operation being performed
    operation: []const u8,
    /// File path if applicable
    file_path: ?[]const u8 = null,
    /// Line number if applicable
    line_number: ?u32 = null,
    /// Column number if applicable
    column_number: ?u32 = null,
    /// Additional context information
    details: ?[]const u8 = null,
    /// Suggested action for the user
    suggestion: ?[]const u8 = null,
    /// Timestamp when error occurred
    timestamp: i64,
    
    /// Create error context with current timestamp
    pub fn init(
        err: anyerror,
        severity: ErrorSeverity,
        operation: []const u8,
    ) ErrorContext {
        return ErrorContext{
            .err = err,
            .severity = severity,
            .operation = operation,
            .timestamp = std.time.timestamp(),
        };
    }
    
    /// Add file location information
    pub fn withLocation(
        self: ErrorContext,
        file_path: []const u8,
        line: ?u32,
        column: ?u32,
    ) ErrorContext {
        var ctx = self;
        ctx.file_path = file_path;
        ctx.line_number = line;
        ctx.column_number = column;
        return ctx;
    }
    
    /// Add additional details
    pub fn withDetails(self: ErrorContext, details: []const u8) ErrorContext {
        var ctx = self;
        ctx.details = details;
        return ctx;
    }
    
    /// Add suggestion for resolution
    pub fn withSuggestion(self: ErrorContext, suggestion: []const u8) ErrorContext {
        var ctx = self;
        ctx.suggestion = suggestion;
        return ctx;
    }
    
    /// Format error for display
    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        const color = self.severity.getColor();
        const reset = "\x1b[0m";
        const bold = "\x1b[1m";
        
        // Error header
        try writer.print("{s}{s}{s} {s}{s}\n", .{
            color,
            bold,
            self.severity.getPrefix(),
            @errorName(self.err),
            reset,
        });
        
        // Operation context
        try writer.print("  Operation: {s}\n", .{self.operation});
        
        // File location if available
        if (self.file_path) |path| {
            try writer.print("  Location: {s}", .{path});
            if (self.line_number) |line| {
                try writer.print(":{d}", .{line});
                if (self.column_number) |col| {
                    try writer.print(":{d}", .{col});
                }
            }
            try writer.print("\n", .{});
        }
        
        // Additional details
        if (self.details) |details| {
            try writer.print("  Details: {s}\n", .{details});
        }
        
        // Suggestion
        if (self.suggestion) |suggestion| {
            try writer.print("  {s}💡 Suggestion:{s} {s}\n", .{
                "\x1b[92m", // Bright green
                reset,
                suggestion,
            });
        }
    }
};

/// Recovery strategy for errors
pub const RecoveryStrategy = enum {
    fail_fast,                    // Stop immediately
    fallback_to_eco_mode,        // Try ECO mode
    fallback_to_scalar,          // Try scalar processing
    retry_with_reduced_parallelism, // Reduce thread count
    retry_with_smaller_chunks,   // Reduce chunk size
    skip_optimizations,          // Disable SIMD/parallel
    use_streaming,               // Switch to streaming mode
    
    /// Get recovery strategy for specific error
    pub fn forError(err: anyerror) RecoveryStrategy {
        return switch (err) {
            error.OutOfMemory => .fallback_to_eco_mode,
            error.SimdNotSupported => .fallback_to_scalar,
            error.ThreadCreationFailed => .retry_with_reduced_parallelism,
            error.JsonTooLarge => .use_streaming,
            error.PerformanceThresholdNotMet => .skip_optimizations,
            else => .fail_fast,
        };
    }
    
    /// Get human-readable description
    pub fn getDescription(self: RecoveryStrategy) []const u8 {
        return switch (self) {
            .fail_fast => "Stop processing immediately",
            .fallback_to_eco_mode => "Switch to memory-efficient ECO mode",
            .fallback_to_scalar => "Use single-threaded scalar processing",
            .retry_with_reduced_parallelism => "Reduce number of threads",
            .retry_with_smaller_chunks => "Process smaller chunks",
            .skip_optimizations => "Disable performance optimizations",
            .use_streaming => "Switch to streaming mode for large files",
        };
    }
};

/// Error handler with recovery capabilities
pub const ErrorHandler = struct {
    /// Current error context stack
    contexts: std.ArrayList(ErrorContext),
    /// Recovery strategies to attempt
    recovery_strategies: std.ArrayList(RecoveryStrategy),
    /// Error reporting configuration
    config: ErrorConfig,
    /// Statistics
    stats: ErrorStats,
    
    allocator: std.mem.Allocator,
    
    /// Initialize error handler
    pub fn init(allocator: std.mem.Allocator, config: ErrorConfig) ErrorHandler {
        return ErrorHandler{
            .contexts = std.ArrayList(ErrorContext).init(allocator),
            .recovery_strategies = std.ArrayList(RecoveryStrategy).init(allocator),
            .config = config,
            .stats = ErrorStats{},
            .allocator = allocator,
        };
    }
    
    /// Deinitialize error handler
    pub fn deinit(self: *ErrorHandler) void {
        self.contexts.deinit();
        self.recovery_strategies.deinit();
    }
    
    /// Handle an error with context
    pub fn handle(self: *ErrorHandler, context: ErrorContext) !void {
        // Track statistics
        self.stats.total_errors += 1;
        switch (context.severity) {
            .warning => self.stats.warnings += 1,
            .error => self.stats.errors += 1,
            .critical => self.stats.critical_errors += 1,
            else => {},
        }
        
        // Add to context stack
        try self.contexts.append(context);
        
        // Report error if enabled
        if (self.config.report_errors) {
            try self.reportError(context);
        }
        
        // Determine recovery strategy
        const strategy = RecoveryStrategy.forError(context.err);
        if (strategy != .fail_fast and self.config.enable_recovery) {
            try self.recovery_strategies.append(strategy);
        } else if (context.severity == .critical or self.config.fail_fast) {
            return context.err;
        }
    }
    
    /// Report error to configured output
    fn reportError(self: *ErrorHandler, context: ErrorContext) !void {
        const writer = std.io.getStdErr().writer();
        
        if (self.config.use_color and std.io.getStdErr().isTty()) {
            try writer.print("{}", .{context});
        } else {
            // Plain text output
            try writer.print("{s} {s} in {s}", .{
                context.severity.getPrefix(),
                @errorName(context.err),
                context.operation,
            });
            
            if (context.file_path) |path| {
                try writer.print(" at {s}", .{path});
                if (context.line_number) |line| {
                    try writer.print(":{d}", .{line});
                }
            }
            
            try writer.print("\n", .{});
        }
    }
    
    /// Get next recovery strategy to try
    pub fn getRecoveryStrategy(self: *ErrorHandler) ?RecoveryStrategy {
        if (self.recovery_strategies.items.len == 0) return null;
        return self.recovery_strategies.pop();
    }
    
    /// Clear error contexts after successful recovery
    pub fn clearContexts(self: *ErrorHandler) void {
        self.contexts.clearRetainingCapacity();
    }
    
    /// Get error summary
    pub fn getSummary(self: *ErrorHandler) ErrorStats {
        return self.stats;
    }
};

/// Error handler configuration
pub const ErrorConfig = struct {
    /// Report errors to stderr
    report_errors: bool = true,
    /// Use colored output
    use_color: bool = true,
    /// Enable automatic recovery
    enable_recovery: bool = true,
    /// Fail on first error
    fail_fast: bool = false,
    /// Maximum recovery attempts
    max_recovery_attempts: u32 = 3,
    /// Log errors to file
    log_file: ?[]const u8 = null,
};

/// Error statistics
pub const ErrorStats = struct {
    total_errors: u64 = 0,
    warnings: u64 = 0,
    errors: u64 = 0,
    critical_errors: u64 = 0,
    recovered_errors: u64 = 0,
    
    pub fn hasErrors(self: ErrorStats) bool {
        return self.errors > 0 or self.critical_errors > 0;
    }
    
    pub fn format(
        self: ErrorStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("Errors: {d} ({d} critical, {d} recovered), Warnings: {d}", .{
            self.errors + self.critical_errors,
            self.critical_errors,
            self.recovered_errors,
            self.warnings,
        });
    }
};

/// Common error contexts with suggestions
pub const CommonErrors = struct {
    pub fn outOfMemory(size: u64) ErrorContext {
        return ErrorContext.init(error.OutOfMemory, .error, "Memory allocation")
            .withDetails(std.fmt.allocPrint(
                std.heap.page_allocator,
                "Failed to allocate {d} bytes",
                .{size},
            ) catch "Failed to allocate memory")
            .withSuggestion("Try using ECO mode for memory-constrained processing");
    }
    
    pub fn fileNotFound(path: []const u8) ErrorContext {
        return ErrorContext.init(error.FileNotFound, .error, "File access")
            .withLocation(path, null, null)
            .withSuggestion("Check if the file exists and you have read permissions");
    }
    
    pub fn invalidJson(path: []const u8, line: u32, col: u32, reason: []const u8) ErrorContext {
        return ErrorContext.init(error.InvalidJson, .error, "JSON parsing")
            .withLocation(path, line, col)
            .withDetails(reason)
            .withSuggestion("Validate your JSON with a linter or online validator");
    }
    
    pub fn performanceThreshold(expected: f64, actual: f64) ErrorContext {
        return ErrorContext.init(error.PerformanceThresholdNotMet, .warning, "Performance check")
            .withDetails(std.fmt.allocPrint(
                std.heap.page_allocator,
                "Expected {d:.2} MB/s, got {d:.2} MB/s",
                .{ expected, actual },
            ) catch "Performance below threshold")
            .withSuggestion("Consider using TURBO mode or checking system load");
    }
};

// Tests
test "error context formatting" {
    const ctx = ErrorContext.init(error.OutOfMemory, .error, "Test operation")
        .withLocation("test.json", 42, 13)
        .withDetails("Failed to allocate 1GB")
        .withSuggestion("Use ECO mode");
    
    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try stream.writer().print("{}", .{ctx});
    
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "OutOfMemory") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test.json:42:13") != null);
}

test "recovery strategy selection" {
    try std.testing.expectEqual(
        RecoveryStrategy.fallback_to_eco_mode,
        RecoveryStrategy.forError(error.OutOfMemory)
    );
    
    try std.testing.expectEqual(
        RecoveryStrategy.fallback_to_scalar,
        RecoveryStrategy.forError(error.SimdNotSupported)
    );
}