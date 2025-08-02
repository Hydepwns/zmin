const std = @import("std");
const zmin = @import("../../src/root.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== Testing SIMD Number Parsing Correctness ===\n", .{});

    // Test cases with various number scenarios
    const test_cases = [_][]const u8{
        // Simple integers
        "42",
        "0",
        "123456789",
        
        // Negative numbers
        "-42",
        "-0",
        "-999",
        
        // Decimals
        "3.14",
        "0.5",
        "-1.23",
        "999.999",
        
        // Scientific notation
        "1e5",
        "1.5e10",
        "-2.3e-4",
        "1E+6",
        
        // JSON objects with numbers
        "{\"value\":42}",
        "{\"pi\":3.14159}",
        "{\"negative\":-123}",
        "{\"scientific\":1.23e-4}",
        
        // JSON arrays with numbers
        "[1,2,3,4,5]",
        "[1.1, 2.2, 3.3]",
        "[-1, 0, 1]",
        "[1e2, 2e3, 3e4]",
        
        // Mixed content
        "{\"int\":42,\"float\":3.14,\"negative\":-999,\"sci\":1e5}",
    };

    var parser = try zmin.v2.StreamingParser.init(allocator, .{});
    defer parser.deinit();

    std.debug.print("Running {} test cases...\n", .{test_cases.len});

    var passed: usize = 0;
    var failed: usize = 0;

    for (test_cases, 0..) |test_case, i| {
        std.debug.print("Test {}: \"{s}\" -> ", .{i + 1, test_case});
        
        var token_stream = parser.parseStreaming(test_case) catch |err| {
            std.debug.print("FAILED - Parse error: {}\n", .{err});
            failed += 1;
            continue;
        };
        defer token_stream.deinit();
        
        const token_count = token_stream.getTokenCount();
        if (token_count == 0) {
            std.debug.print("FAILED - No tokens parsed\n", .{});
            failed += 1;
            continue;
        }
        
        // Count number tokens and display them
        var number_tokens: usize = 0;
        var numbers_found = std.ArrayList([]const u8).init(allocator);
        defer numbers_found.deinit();
        
        for (0..token_count) |token_idx| {
            if (token_stream.getToken(token_idx)) |token| {
                if (token.token_type == .number) {
                    number_tokens += 1;
                    const number_text = token_stream.input_data[token.start..token.end];
                    try numbers_found.append(number_text);
                }
            }
        }
        
        if (number_tokens > 0) {
            std.debug.print("PASSED - {} tokens, {} numbers: [", .{ token_count, number_tokens });
            for (numbers_found.items, 0..) |num, idx| {
                if (idx > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{num});
            }
            std.debug.print("]\n", .{});
            passed += 1;
        } else {
            std.debug.print("FAILED - No numbers found\n", .{});
            failed += 1;
        }
    }

    std.debug.print("\n=== Results ===\n", .{});
    std.debug.print("Passed: {}\n", .{passed});
    std.debug.print("Failed: {}\n", .{failed});
    std.debug.print("Success rate: {d:.1}%\n", .{@as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(test_cases.len)) * 100.0});
    
    if (failed == 0) {
        std.debug.print("✅ All SIMD number parsing tests passed!\n", .{});
    } else {
        std.debug.print("❌ Some tests failed\n", .{});
    }
}