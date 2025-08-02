const std = @import("std");
const zmin = @import("../../src/root.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== Testing SIMD String Parsing Correctness ===\n", .{});

    // Test cases with various string scenarios
    const test_cases = [_][]const u8{
        // Simple strings
        "\"hello\"",
        "\"world\"",
        
        // Long strings that should trigger SIMD processing (>64 chars)
        "\"This is a very long string that should definitely trigger the SIMD processing path because it contains way more than 64 characters which is the chunk size for AVX-512 vector operations\"",
        
        // Strings with escape sequences
        "\"hello\\\"world\\\"\"",
        "\"line1\\nline2\"",
        "\"tab\\there\"",
        "\"backslash\\\\test\"",
        
        // Empty string
        "\"\"",
        
        // String with unicode (should be handled correctly)
        "\"Hello 世界 🌍\"",
        
        // JSON objects with strings
        "{\"key\":\"value\"}",
        "{\"name\":\"A very long name that should trigger SIMD processing because it exceeds the 64-byte chunk size used by AVX-512 vector operations\"}",
        
        // JSON arrays with strings
        "[\"short\",\"This is another very long string designed to test the SIMD string parsing implementation with realistic data\"]",
    };

    var parser = try zmin.v2.StreamingParser.init(allocator, .{});
    defer parser.deinit();

    std.debug.print("Running {} test cases...\n", .{test_cases.len});

    var passed: usize = 0;
    var failed: usize = 0;

    for (test_cases, 0..) |test_case, i| {
        std.debug.print("Test {}: ", .{i + 1});
        
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
        
        // Count string tokens
        var string_tokens: usize = 0;
        for (0..token_count) |token_idx| {
            if (token_stream.getToken(token_idx)) |token| {
                if (token.token_type == .string) {
                    string_tokens += 1;
                }
            }
        }
        
        std.debug.print("PASSED - {} tokens, {} strings\n", .{ token_count, string_tokens });
        passed += 1;
    }

    std.debug.print("\n=== Results ===\n", .{});
    std.debug.print("Passed: {}\n", .{passed});
    std.debug.print("Failed: {}\n", .{failed});
    std.debug.print("Success rate: {d:.1}%\n", .{@as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(test_cases.len)) * 100.0});
    
    if (failed == 0) {
        std.debug.print("✅ All SIMD string parsing tests passed!\n", .{});
    } else {
        std.debug.print("❌ Some tests failed\n", .{});
    }
}