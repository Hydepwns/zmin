const std = @import("std");
const error_handling = @import("src/v2/error_handling.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    std.debug.print("Testing Error Handling System...\n", .{});
    
    // Test 1: Basic error handler functionality
    {
        var handler = error_handling.ErrorHandler.init(allocator, .{
            .default_strategy = .SkipAndContinue,
            .collect_errors = true,
            .max_errors = 10,
        });
        defer handler.deinit();
        
        const context = error_handling.ErrorContext{
            .error_type = .InvalidNumber,
            .message = "Invalid number format",
            .position = 42,
            .timestamp = std.time.milliTimestamp(),
        };
        
        const action = try handler.handleError(context);
        std.debug.print("Test 1 - Basic functionality: ", .{});
        if (action.action == .Skip and handler.getErrorCount() == 1) {
            std.debug.print("PASS\n", .{});
        } else {
            std.debug.print("FAIL\n", .{});
        }
    }
    
    // Test 2: Error accumulator
    {
        var accumulator = error_handling.ErrorAccumulator.init(allocator);
        defer accumulator.deinit();
        
        try accumulator.recordError(.InvalidNumber, 2);
        try accumulator.recordError(.UnexpectedCharacter, 1);
        try accumulator.recordError(.DepthLimitExceeded, 3);
        
        std.debug.print("Test 2 - Error accumulator: ", .{});
        if (accumulator.total_errors == 3 and accumulator.fatal_errors == 1 and accumulator.warnings == 1) {
            std.debug.print("PASS\n", .{});
        } else {
            std.debug.print("FAIL (total: {}, fatal: {}, warnings: {})\n", .{
                accumulator.total_errors, accumulator.fatal_errors, accumulator.warnings
            });
        }
        
        const report = try accumulator.getReport(allocator);
        defer allocator.free(report);
        std.debug.print("Generated report ({} chars)\n", .{report.len});
    }
    
    // Test 3: Custom recovery function
    {
        const CustomFn = struct {
            fn customRecovery(context: error_handling.ErrorContext) !error_handling.RecoveryAction {
                return switch (context.error_type) {
                    .InvalidNumber => error_handling.RecoveryAction{
                        .action = .Repair,
                        .repair_data = "42",
                        .skip_bytes = 5,
                    },
                    else => error_handling.RecoveryAction{ .action = .Continue },
                };
            }
        };
        
        var handler = error_handling.ErrorHandler.init(allocator, .{
            .default_strategy = .Custom,
            .custom_recovery_fn = CustomFn.customRecovery,
        });
        defer handler.deinit();
        
        const context = error_handling.ErrorContext{
            .error_type = .InvalidNumber,
            .message = "Bad number",
            .position = 20,
            .timestamp = std.time.milliTimestamp(),
        };
        
        const action = try handler.handleError(context);
        std.debug.print("Test 3 - Custom recovery: ", .{});
        std.debug.print("Action: {}, repair_data: {?s}, skip_bytes: {}\n", .{action.action, action.repair_data, action.skip_bytes});
        if (action.action == .Repair and 
            action.repair_data != null and 
            std.mem.eql(u8, action.repair_data.?, "42")) {
            std.debug.print("PASS\n", .{});
        } else {
            std.debug.print("FAIL\n", .{});
        }
    }
    
    std.debug.print("\nError handling system tests completed!\n", .{});
}