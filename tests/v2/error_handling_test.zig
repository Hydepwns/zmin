const std = @import("std");
const testing = std.testing;
const error_handling = @import("src/v2/error_handling.zig");
const ErrorHandler = error_handling.ErrorHandler;
const ErrorHandlerConfig = error_handling.ErrorHandlerConfig;
const ErrorContext = error_handling.ErrorContext;
const ErrorType = error_handling.ErrorType;
const RecoveryStrategy = error_handling.RecoveryStrategy;
const RecoveryAction = error_handling.RecoveryAction;
const ErrorAccumulator = error_handling.ErrorAccumulator;

test "ErrorHandler - basic functionality" {
    const allocator = testing.allocator;
    
    var handler = ErrorHandler.init(allocator, .{
        .default_strategy = .SkipAndContinue,
        .collect_errors = true,
        .max_errors = 10,
    });
    defer handler.deinit();
    
    const context = ErrorContext{
        .error_type = .InvalidNumber,
        .message = "Invalid number format",
        .position = 42,
        .timestamp = std.time.milliTimestamp(),
    };
    
    const action = try handler.handleError(context);
    try testing.expect(action.action == .Skip);
    try testing.expect(handler.getErrorCount() == 1);
    
    const errors = handler.getErrors();
    try testing.expect(errors.len == 1);
    try testing.expect(errors[0].error_type == .InvalidNumber);
}

test "ErrorHandler - stop on max errors" {
    const allocator = testing.allocator;
    
    var handler = ErrorHandler.init(allocator, .{
        .default_strategy = .SkipAndContinue,
        .max_errors = 2,
        .collect_errors = true,
    });
    defer handler.deinit();
    
    const context = ErrorContext{
        .error_type = .UnexpectedCharacter,
        .message = "Unexpected character",
        .position = 10,
        .timestamp = std.time.milliTimestamp(),
    };
    
    // First two errors should be handled normally
    _ = try handler.handleError(context);
    _ = try handler.handleError(context);
    
    // Third error should trigger stop
    const action = try handler.handleError(context);
    try testing.expect(action.action == .Stop);
    try testing.expect(handler.getErrorCount() == 3);
}

test "ErrorHandler - severity threshold" {
    const allocator = testing.allocator;
    
    var handler = ErrorHandler.init(allocator, .{
        .default_strategy = .StopOnError,
        .severity_threshold = 2, // Only handle errors with severity >= 2
        .collect_errors = true,
    });
    defer handler.deinit();
    
    // Low severity error should be ignored
    const low_severity_context = ErrorContext{
        .error_type = .InvalidNumber,
        .message = "Low severity",
        .position = 5,
        .severity = 1,
        .timestamp = std.time.milliTimestamp(),
    };
    
    const action1 = try handler.handleError(low_severity_context);
    try testing.expect(action1.action == .Continue);
    try testing.expect(handler.getErrorCount() == 1);
    
    // High severity error should be handled
    const high_severity_context = ErrorContext{
        .error_type = .DepthLimitExceeded,
        .message = "High severity",
        .position = 10,
        .severity = 3,
        .timestamp = std.time.milliTimestamp(),
    };
    
    const action2 = try handler.handleError(high_severity_context);
    try testing.expect(action2.action == .Stop);
    try testing.expect(handler.getErrorCount() == 2);
}

test "ErrorHandler - repair strategy" {
    const allocator = testing.allocator;
    
    var handler = ErrorHandler.init(allocator, .{
        .default_strategy = .TryRepair,
        .collect_errors = true,
    });
    defer handler.deinit();
    
    // Test invalid escape sequence repair
    const escape_context = ErrorContext{
        .error_type = .InvalidEscapeSequence,
        .message = "Invalid escape sequence",
        .position = 15,
        .timestamp = std.time.milliTimestamp(),
    };
    
    const action = try handler.handleError(escape_context);
    try testing.expect(action.action == .Repair);
    try testing.expect(action.skip_bytes == 2);
    try testing.expect(std.mem.eql(u8, action.repair_data.?, "?"));
}

test "ErrorHandler - custom recovery function" {
    const allocator = testing.allocator;
    
    const CustomFn = struct {
        fn customRecovery(context: ErrorContext) !RecoveryAction {
            return switch (context.error_type) {
                .InvalidNumber => RecoveryAction{
                    .action = .Repair,
                    .repair_data = "42",
                    .skip_bytes = 5,
                },
                else => RecoveryAction{ .action = .Continue },
            };
        }
    };
    
    var handler = ErrorHandler.init(allocator, .{
        .default_strategy = .Custom,
        .custom_recovery_fn = CustomFn.customRecovery,
        .collect_errors = true,
    });
    defer handler.deinit();
    
    const context = ErrorContext{
        .error_type = .InvalidNumber,
        .message = "Bad number",
        .position = 20,
        .timestamp = std.time.milliTimestamp(),
    };
    
    const action = try handler.handleError(context);
    try testing.expect(action.action == .Repair);
    try testing.expect(std.mem.eql(u8, action.repair_data.?, "42"));
    try testing.expect(action.skip_bytes == 5);
}

test "ErrorAccumulator - error tracking" {
    const allocator = testing.allocator;
    
    var accumulator = ErrorAccumulator.init(allocator);
    defer accumulator.deinit();
    
    // Record various errors
    try accumulator.recordError(.InvalidNumber, 2);
    try accumulator.recordError(.InvalidNumber, 2);
    try accumulator.recordError(.UnexpectedCharacter, 1); // Warning
    try accumulator.recordError(.DepthLimitExceeded, 3); // Fatal
    
    try testing.expect(accumulator.total_errors == 4);
    try testing.expect(accumulator.fatal_errors == 1);
    try testing.expect(accumulator.warnings == 1);
    
    // Test report generation
    const report = try accumulator.getReport(allocator);
    defer allocator.free(report);
    
    try testing.expect(report.len > 0);
    try testing.expect(std.mem.indexOf(u8, report, "Total Errors: 4") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Fatal Errors: 1") != null);
    try testing.expect(std.mem.indexOf(u8, report, "Warnings: 1") != null);
}

test "ErrorHandler - clear errors" {
    const allocator = testing.allocator;
    
    var handler = ErrorHandler.init(allocator, .{
        .collect_errors = true,
    });
    defer handler.deinit();
    
    const context = ErrorContext{
        .error_type = .InvalidNumber,
        .message = "Test error",
        .position = 5,
        .timestamp = std.time.milliTimestamp(),
    };
    
    _ = try handler.handleError(context);
    try testing.expect(handler.getErrorCount() == 1);
    
    handler.clearErrors();
    try testing.expect(handler.getErrorCount() == 0);
    try testing.expect(handler.getErrors().len == 0);
}

test "ErrorContext - formatting" {
    const context = ErrorContext{
        .error_type = .UnexpectedCharacter,
        .message = "Unexpected character 'x'",
        .position = 25,
        .line = 3,
        .column = 10,
        .timestamp = std.time.milliTimestamp(),
    };
    
    var buffer: [256]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buffer, "{}", .{context});
    
    try testing.expect(std.mem.indexOf(u8, formatted, "Unexpected character 'x'") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "position 25") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "line 3") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "column 10") != null);
}