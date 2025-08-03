const std = @import("std");
const zmin = @import("zmin_lib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n=== zmin v2.0 Error Handling Demo ===\n\n", .{});
    
    // Initialize error handler
    const error_config = zmin.v2.error_handling.ErrorHandlerConfig{
        .default_strategy = .SkipAndContinue,
        .max_errors = 50,
        .enable_logging = true,
        .collect_errors = true,
        .severity_threshold = 1,
    };
    
    var error_handler = zmin.v2.error_handling.ErrorHandler.init(allocator, error_config);
    defer error_handler.deinit();
    
    // Initialize parser with error recovery enabled
    const parser_config = zmin.v2.ParserConfig{
        .enable_error_recovery = true,
        .max_errors = 50,
        .collect_errors = true,
    };
    
    var parser = try zmin.v2.StreamingParser.init(allocator, parser_config);
    defer parser.deinit();
    
    // Set error handler
    parser.setErrorHandler(&error_handler);
    
    // Example 1: JSON with invalid escape sequences
    {
        std.debug.print("Example 1: Handling invalid escape sequences\n", .{});
        
        const malformed_json = 
            \\{
            \\  "name": "John\\xDoe",
            \\  "description": "A\\qtest",
            \\  "value": 42
            \\}
        ;
        
        std.debug.print("Input: {s}\n", .{malformed_json});
        
        var token_stream = parser.parseStreaming(malformed_json) catch |err| blk: {
            std.debug.print("Parse error: {}\n", .{err});
            break :blk null;
        };
        
        if (token_stream) |stream| {
            defer stream.deinit();
            
            // Process the token stream despite errors
            var engine = try zmin.v2.ZminEngine.init(allocator, .{});
            defer engine.deinit();
            
            const result = engine.processToString(allocator, malformed_json) catch |err| blk: {
                std.debug.print("Processing failed: {}\n", .{err});
                break :blk null;
            };
            
            if (result) |output| {
                defer allocator.free(output);
                std.debug.print("Recovered output: {s}\n", .{output});
            }
        }
        
        std.debug.print("Errors encountered: {}\n", .{error_handler.getErrorCount()});
        const errors = error_handler.getErrors();
        for (errors) |error_ctx| {
            std.debug.print("  Error: {s} at position {}\n", .{ error_ctx.message, error_ctx.position });
        }
        std.debug.print("\n");
    }
    
    // Reset error handler for next example
    error_handler.clearErrors();
    
    // Example 2: JSON with invalid numbers
    {
        std.debug.print("Example 2: Handling invalid numbers\n", .{});
        
        const json_with_bad_numbers = 
            \\{
            \\  "good_number": 42,
            \\  "bad_number1": 123.456.789,
            \\  "bad_number2": 1e999999,
            \\  "another_field": "valid"
            \\}
        ;
        
        std.debug.print("Input: {s}\n", .{json_with_bad_numbers});
        
        // Try to process with best effort recovery
        const recovery_config = zmin.v2.error_handling.ErrorHandlerConfig{
            .default_strategy = .BestEffort,
            .max_errors = 100,
            .enable_logging = false, // Reduce noise for this example
            .collect_errors = true,
        };
        
        var recovery_handler = zmin.v2.error_handling.ErrorHandler.init(allocator, recovery_config);
        defer recovery_handler.deinit();
        
        parser.setErrorHandler(&recovery_handler);
        
        var engine = try zmin.v2.ZminEngine.init(allocator, .{});
        defer engine.deinit();
        
        const result = engine.processToString(allocator, json_with_bad_numbers) catch |err| blk: {
            std.debug.print("Processing with recovery failed: {}\n", .{err});
            break :blk null;
        };
        
        if (result) |output| {
            defer allocator.free(output);
            std.debug.print("Best effort output: {s}\n", .{output});
        }
        
        std.debug.print("Recovery errors: {}\n", .{recovery_handler.getErrorCount()});
        std.debug.print("\n");
    }
    
    // Example 3: Error accumulation and reporting
    {
        std.debug.print("Example 3: Error accumulation and reporting\n", .{});
        
        var accumulator = zmin.v2.error_handling.ErrorAccumulator.init(allocator);
        defer accumulator.deinit();
        
        // Simulate processing multiple documents with errors
        const error_types = [_]zmin.v2.error_handling.ErrorType{
            .InvalidNumber,
            .InvalidEscapeSequence,
            .UnexpectedCharacter,
            .InvalidNumber,
            .DepthLimitExceeded,
            .InvalidEscapeSequence,
            .InvalidNumber,
        };
        
        const severities = [_]u8{ 2, 1, 2, 2, 3, 1, 2 };
        
        for (error_types, severities) |error_type, severity| {
            try accumulator.recordError(error_type, severity);
        }
        
        const report = try accumulator.getReport(allocator);
        defer allocator.free(report);
        
        std.debug.print("{s}\n", .{report});
    }
    
    // Example 4: Custom recovery function
    {
        std.debug.print("Example 4: Custom recovery strategies\n", .{});
        
        const CustomRecovery = struct {
            fn customRecoveryFn(context: zmin.v2.error_handling.ErrorContext) !zmin.v2.error_handling.RecoveryAction {
                std.debug.print("Custom recovery for: {s}\n", .{context.message});
                
                return switch (context.error_type) {
                    .InvalidNumber => zmin.v2.error_handling.RecoveryAction{
                        .action = .Repair,
                        .repair_data = "0", // Replace invalid numbers with 0
                        .skip_bytes = 10, // Skip up to 10 characters
                    },
                    .InvalidEscapeSequence => zmin.v2.error_handling.RecoveryAction{
                        .action = .Repair,
                        .repair_data = "?", // Replace with placeholder
                        .skip_bytes = 2,
                    },
                    else => zmin.v2.error_handling.RecoveryAction{
                        .action = .Continue,
                    },
                };
            }
        };
        
        const custom_config = zmin.v2.error_handling.ErrorHandlerConfig{
            .default_strategy = .Custom,
            .custom_recovery_fn = CustomRecovery.customRecoveryFn,
            .max_errors = 20,
            .collect_errors = true,
        };
        
        var custom_handler = zmin.v2.error_handling.ErrorHandler.init(allocator, custom_config);
        defer custom_handler.deinit();
        
        // Test custom recovery with problematic JSON
        const context1 = zmin.v2.error_handling.ErrorContext{
            .error_type = .InvalidNumber,
            .message = "Invalid number format: 123.abc",
            .position = 15,
            .timestamp = std.time.milliTimestamp(),
        };
        
        const action1 = try custom_handler.handleError(context1);
        std.debug.print("Action for invalid number: {s}, repair: {?s}\n", .{ 
            @tagName(action1.action), 
            action1.repair_data 
        });
        
        const context2 = zmin.v2.error_handling.ErrorContext{
            .error_type = .InvalidEscapeSequence,
            .message = "Invalid escape: \\q",
            .position = 25,
            .timestamp = std.time.milliTimestamp(),
        };
        
        const action2 = try custom_handler.handleError(context2);
        std.debug.print("Action for invalid escape: {s}, repair: {?s}\n", .{ 
            @tagName(action2.action), 
            action2.repair_data 
        });
        
        std.debug.print("Custom handler processed {} errors\n", .{custom_handler.getErrorCount()});
    }
    
    std.debug.print("\n✅ Error handling demonstration complete!\n");
}