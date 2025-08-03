const std = @import("std");
const Token = @import("streaming/parser.zig").Token;
const TokenType = @import("streaming/parser.zig").TokenType;

/// Error types for v2 streaming engine
pub const ErrorType = enum {
    // Parser errors
    UnexpectedCharacter,
    UnexpectedEndOfInput,
    InvalidEscapeSequence,
    InvalidUnicodeEscape,
    InvalidNumber,
    NumberOverflow,
    DepthLimitExceeded,
    InvalidUtf8,
    
    // Transformation errors
    TransformationFailed,
    InvalidConfiguration,
    MemoryAllocationFailed,
    OutputBufferFull,
    
    // Schema validation errors
    SchemaViolation,
    TypeMismatch,
    RequiredFieldMissing,
    InvalidFormat,
    
    // System errors
    FileReadError,
    FileWriteError,
    NetworkError,
    TimeoutError,
    
    // Custom errors
    UserDefined,
};

/// Error recovery strategies
pub const RecoveryStrategy = enum {
    /// Stop processing immediately
    StopOnError,
    
    /// Skip the problematic token/section and continue
    SkipAndContinue,
    
    /// Try to repair the error and continue
    TryRepair,
    
    /// Log error and continue with best effort
    BestEffort,
    
    /// Use custom recovery function
    Custom,
};

/// Error context information
pub const ErrorContext = struct {
    /// Type of error
    error_type: ErrorType,
    
    /// Human-readable error message
    message: []const u8,
    
    /// Position in input where error occurred
    position: usize,
    
    /// Line number (if tracked)
    line: ?usize = null,
    
    /// Column number (if tracked)
    column: ?usize = null,
    
    /// Token that caused the error (if applicable)
    token: ?Token = null,
    
    /// Additional context data
    context_data: ?[]const u8 = null,
    
    /// Severity level (0 = info, 1 = warning, 2 = error, 3 = fatal)
    severity: u8 = 2,
    
    /// Timestamp when error occurred
    timestamp: i64,
    
    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("Error: {s} at position {}", .{ self.message, self.position });
        if (self.line != null and self.column != null) {
            try writer.print(" (line {}, column {})", .{ self.line.?, self.column.? });
        }
    }
};

/// Error handler configuration
pub const ErrorHandlerConfig = struct {
    /// Default recovery strategy
    default_strategy: RecoveryStrategy = .StopOnError,
    
    /// Maximum errors before stopping
    max_errors: usize = 100,
    
    /// Enable error logging
    enable_logging: bool = true,
    
    /// Enable error collection
    collect_errors: bool = false,
    
    /// Custom recovery function
    custom_recovery_fn: ?*const fn (context: ErrorContext) anyerror!RecoveryAction = null,
    
    /// Error severity threshold (only handle errors above this level)
    severity_threshold: u8 = 1,
};

/// Recovery action to take
pub const RecoveryAction = struct {
    /// What to do next
    action: enum {
        Continue,
        Skip,
        Repair,
        Stop,
    },
    
    /// If repairing, the replacement data
    repair_data: ?[]const u8 = null,
    
    /// Number of bytes to skip
    skip_bytes: usize = 0,
};

/// Error handler for streaming operations
pub const ErrorHandler = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    config: ErrorHandlerConfig,
    errors: std.ArrayList(ErrorContext),
    error_count: usize = 0,
    
    pub fn init(allocator: std.mem.Allocator, config: ErrorHandlerConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .errors = std.ArrayList(ErrorContext).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.errors.deinit();
    }
    
    /// Handle an error during processing
    pub fn handleError(self: *Self, context: ErrorContext) !RecoveryAction {
        self.error_count += 1;
        
        // Check if we've exceeded max errors
        if (self.error_count > self.config.max_errors) {
            return RecoveryAction{ .action = .Stop };
        }
        
        // Check severity threshold
        if (context.severity < self.config.severity_threshold) {
            return RecoveryAction{ .action = .Continue };
        }
        
        // Log error if enabled
        if (self.config.enable_logging) {
            std.log.err("{}", .{context});
        }
        
        // Collect error if enabled
        if (self.config.collect_errors) {
            try self.errors.append(context);
        }
        
        // Determine recovery action
        const strategy = self.determineStrategy(context);
        
        return switch (strategy) {
            .StopOnError => RecoveryAction{ .action = .Stop },
            .SkipAndContinue => self.skipStrategy(context),
            .TryRepair => self.repairStrategy(context),
            .BestEffort => self.bestEffortStrategy(context),
            .Custom => if (self.config.custom_recovery_fn) |custom_fn|
                try custom_fn(context)
            else
                RecoveryAction{ .action = .Stop },
        };
    }
    
    /// Get all collected errors
    pub fn getErrors(self: *const Self) []const ErrorContext {
        return self.errors.items;
    }
    
    /// Get error count
    pub fn getErrorCount(self: *const Self) usize {
        return self.error_count;
    }
    
    /// Clear error history
    pub fn clearErrors(self: *Self) void {
        self.errors.clearRetainingCapacity();
        self.error_count = 0;
    }
    
    /// Create error context with current state
    pub fn createError(
        self: *const Self,
        error_type: ErrorType,
        message: []const u8,
        position: usize,
    ) ErrorContext {
        _ = self;
        return ErrorContext{
            .error_type = error_type,
            .message = message,
            .position = position,
            .timestamp = std.time.milliTimestamp(),
        };
    }
    
    fn determineStrategy(self: *const Self, context: ErrorContext) RecoveryStrategy {
        // If custom strategy is configured, use it
        if (self.config.default_strategy == .Custom) {
            return .Custom;
        }
        
        // Use appropriate strategy for specific error types
        return switch (context.error_type) {
            .InvalidEscapeSequence, .InvalidUnicodeEscape => .TryRepair,
            .UnexpectedCharacter => .SkipAndContinue,
            .InvalidNumber => .SkipAndContinue,
            .DepthLimitExceeded, .NumberOverflow => .StopOnError,
            else => self.config.default_strategy,
        };
    }
    
    fn skipStrategy(self: *const Self, context: ErrorContext) RecoveryAction {
        _ = self;
        // Determine how many bytes to skip based on error type
        const skip_bytes: usize = switch (context.error_type) {
            .InvalidEscapeSequence => 2, // Skip backslash and next char
            .UnexpectedCharacter => 1,
            .InvalidNumber => blk: {
                // Skip until we find a delimiter
                if (context.context_data) |data| {
                    var i: usize = 0;
                    while (i < data.len and !isDelimiter(data[i])) : (i += 1) {}
                    break :blk i;
                }
                break :blk 1;
            },
            else => 1,
        };
        
        return RecoveryAction{
            .action = .Skip,
            .skip_bytes = skip_bytes,
        };
    }
    
    fn repairStrategy(self: *const Self, context: ErrorContext) RecoveryAction {
        _ = self;
        // Try to repair certain types of errors
        return switch (context.error_type) {
            .InvalidEscapeSequence => RecoveryAction{
                .action = .Repair,
                .repair_data = "?", // Replace with placeholder
                .skip_bytes = 2,
            },
            .InvalidUnicodeEscape => RecoveryAction{
                .action = .Repair,
                .repair_data = "\\uFFFD", // Unicode replacement character
                .skip_bytes = 6, // Skip \uXXXX
            },
            else => RecoveryAction{ .action = .Skip, .skip_bytes = 1 },
        };
    }
    
    fn bestEffortStrategy(self: *const Self, context: ErrorContext) RecoveryAction {
        _ = self;
        // Best effort: try to continue with minimal disruption
        return switch (context.error_type) {
            .UnexpectedEndOfInput => RecoveryAction{ .action = .Stop },
            .DepthLimitExceeded => RecoveryAction{ .action = .Stop },
            else => RecoveryAction{ .action = .Continue },
        };
    }
    
    fn isDelimiter(char: u8) bool {
        return switch (char) {
            ' ', '\t', '\n', '\r', ',', '}', ']', ':' => true,
            else => false,
        };
    }
};

/// Error accumulator for batch operations
pub const ErrorAccumulator = struct {
    const Self = @This();
    
    errors_by_type: std.AutoHashMap(ErrorType, usize),
    total_errors: usize = 0,
    fatal_errors: usize = 0,
    warnings: usize = 0,
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .errors_by_type = std.AutoHashMap(ErrorType, usize).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.errors_by_type.deinit();
    }
    
    pub fn recordError(self: *Self, error_type: ErrorType, severity: u8) !void {
        const result = try self.errors_by_type.getOrPut(error_type);
        if (!result.found_existing) {
            result.value_ptr.* = 0;
        }
        result.value_ptr.* += 1;
        
        self.total_errors += 1;
        
        if (severity >= 3) {
            self.fatal_errors += 1;
        } else if (severity == 1) {
            self.warnings += 1;
        }
    }
    
    pub fn getReport(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var report = std.ArrayList(u8).init(allocator);
        defer report.deinit();
        
        try report.writer().print("Error Report:\n", .{});
        try report.writer().print("Total Errors: {}\n", .{self.total_errors});
        try report.writer().print("Fatal Errors: {}\n", .{self.fatal_errors});
        try report.writer().print("Warnings: {}\n", .{self.warnings});
        try report.writer().print("\nErrors by Type:\n", .{});
        
        var it = self.errors_by_type.iterator();
        while (it.next()) |entry| {
            try report.writer().print("  {s}: {}\n", .{ @tagName(entry.key_ptr.*), entry.value_ptr.* });
        }
        
        return allocator.dupe(u8, report.items);
    }
};

// Tests
test "ErrorHandler basic functionality" {
    const allocator = std.testing.allocator;
    
    var handler = ErrorHandler.init(allocator, .{
        .default_strategy = .SkipAndContinue,
        .collect_errors = true,
    });
    defer handler.deinit();
    
    const context = ErrorContext{
        .error_type = .InvalidNumber,
        .message = "Invalid number format",
        .position = 42,
        .timestamp = std.time.milliTimestamp(),
    };
    
    const action = try handler.handleError(context);
    try std.testing.expect(action.action == .Skip);
    try std.testing.expect(handler.getErrorCount() == 1);
}

test "ErrorAccumulator" {
    const allocator = std.testing.allocator;
    
    var accumulator = ErrorAccumulator.init(allocator);
    defer accumulator.deinit();
    
    try accumulator.recordError(.InvalidNumber, 2);
    try accumulator.recordError(.InvalidNumber, 2);
    try accumulator.recordError(.UnexpectedCharacter, 2);
    try accumulator.recordError(.DepthLimitExceeded, 3);
    
    try std.testing.expect(accumulator.total_errors == 4);
    try std.testing.expect(accumulator.fatal_errors == 1);
    
    const report = try accumulator.getReport(allocator);
    defer allocator.free(report);
    
    try std.testing.expect(report.len > 0);
}