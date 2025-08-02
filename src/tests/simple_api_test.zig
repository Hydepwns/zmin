//! Tests for the Simple API
//!
//! This test suite validates the simple API functionality including:
//! - Basic minification
//! - Edge cases and error handling
//! - Performance characteristics
//! - Memory safety

const std = @import("std");
const testing = std.testing;
const simple = @import("../api/simple.zig");

test "minify removes whitespace outside strings" {
    const allocator = testing.allocator;
    
    const input = "{ \"name\" : \"John Doe\" , \"age\" : 30 }";
    const expected = "{\"name\":\"John Doe\",\"age\":30}";
    
    const result = try simple.minify(allocator, input);
    defer allocator.free(result);
    
    try testing.expectEqualStrings(expected, result);
}

test "minify preserves whitespace inside strings" {
    const allocator = testing.allocator;
    
    const input = "{ \"message\" : \"Hello   World\" }";
    const expected = "{\"message\":\"Hello   World\"}";
    
    const result = try simple.minify(allocator, input);
    defer allocator.free(result);
    
    try testing.expectEqualStrings(expected, result);
}

test "minify handles empty input" {
    const allocator = testing.allocator;
    
    const result = try simple.minify(allocator, "");
    defer allocator.free(result);
    
    try testing.expectEqualStrings("", result);
}

test "minify handles nested objects" {
    const allocator = testing.allocator;
    
    const input =
        \\{
        \\  "user": {
        \\    "name": "John",
        \\    "details": {
        \\      "age": 30,
        \\      "city": "NYC"
        \\    }
        \\  }
        \\}
    ;
    const expected = "{\"user\":{\"name\":\"John\",\"details\":{\"age\":30,\"city\":\"NYC\"}}}";
    
    const result = try simple.minify(allocator, input);
    defer allocator.free(result);
    
    try testing.expectEqualStrings(expected, result);
}

test "minify handles arrays" {
    const allocator = testing.allocator;
    
    const input = "[ 1 , 2 , 3 , \"four\" , true , null ]";
    const expected = "[1,2,3,\"four\",true,null]";
    
    const result = try simple.minify(allocator, input);
    defer allocator.free(result);
    
    try testing.expectEqualStrings(expected, result);
}

test "minify handles escape sequences" {
    const allocator = testing.allocator;
    
    const input = "{ \"escaped\" : \"\\\"quotes\\\" and \\\\backslash\\\\\" }";
    const expected = "{\"escaped\":\"\\\"quotes\\\" and \\\\backslash\\\\\"}";
    
    const result = try simple.minify(allocator, input);
    defer allocator.free(result);
    
    try testing.expectEqualStrings(expected, result);
}

test "minify handles unicode" {
    const allocator = testing.allocator;
    
    const input = "{ \"emoji\" : \"🎉\" , \"chinese\" : \"你好\" }";
    const expected = "{\"emoji\":\"🎉\",\"chinese\":\"你好\"}";
    
    const result = try simple.minify(allocator, input);
    defer allocator.free(result);
    
    try testing.expectEqualStrings(expected, result);
}

test "minify rejects invalid JSON" {
    const allocator = testing.allocator;
    
    const invalid_inputs = [_][]const u8{
        "{ invalid json }",
        "{ \"unclosed\": \"string }",
        "{ \"key\": }",
        "{ trailing, }",
        "[1, 2, 3,]",
    };
    
    for (invalid_inputs) |input| {
        const result = simple.minify(allocator, input);
        try testing.expectError(error.InvalidJson, result);
    }
}

test "minifyToBuffer works with sufficient buffer" {
    const input = "{ \"key\" : \"value\" }";
    const expected = "{\"key\":\"value\"}";
    
    var buffer: [1024]u8 = undefined;
    const len = try simple.minifyToBuffer(input, &buffer);
    
    try testing.expectEqualStrings(expected, buffer[0..len]);
}

test "minifyToBuffer errors on insufficient buffer" {
    const input = "{ \"key\" : \"value\" }";
    
    var buffer: [5]u8 = undefined;
    const result = simple.minifyToBuffer(input, &buffer);
    
    try testing.expectError(error.BufferTooSmall, result);
}

test "minifyToWriter outputs correctly" {
    const input = "{ \"test\" : true }";
    const expected = "{\"test\":true}";
    
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();
    
    try simple.minifyToWriter(input, output.writer());
    
    try testing.expectEqualStrings(expected, output.items);
}

test "validate accepts valid JSON" {
    const valid_inputs = [_][]const u8{
        "{}",
        "[]",
        "null",
        "true",
        "false",
        "123",
        "\"string\"",
        "{\"key\":\"value\"}",
        "[1,2,3]",
    };
    
    for (valid_inputs) |input| {
        try simple.validate(input);
    }
}

test "validate rejects invalid JSON" {
    const invalid_inputs = [_][]const u8{
        "{",
        "}",
        "{]",
        "{'single':quotes'}",
        "{unquoted:key}",
        "[1,2,3,]",
    };
    
    for (invalid_inputs) |input| {
        const result = simple.validate(input);
        try testing.expectError(error.InvalidJson, result);
    }
}

test "estimateMinifiedSize provides reasonable estimates" {
    const test_cases = [_]struct {
        input: []const u8,
        expected_ratio: f32, // Expected compression ratio
    }{
        .{ .input = "{ \"key\" : \"value\" }", .expected_ratio = 0.7 },
        .{ .input = "{\"already\":\"minified\"}", .expected_ratio = 1.0 },
        .{ .input = "{\n\n\n\n\n}", .expected_ratio = 0.2 },
    };
    
    for (test_cases) |tc| {
        const estimated = simple.estimateMinifiedSize(tc.input);
        const expected_min = @as(usize, @intFromFloat(@as(f32, @floatFromInt(tc.input.len)) * tc.expected_ratio * 0.8));
        const expected_max = @as(usize, @intFromFloat(@as(f32, @floatFromInt(tc.input.len)) * tc.expected_ratio * 1.2));
        
        try testing.expect(estimated >= expected_min);
        try testing.expect(estimated <= expected_max);
    }
}

test "jsonEquals compares semantic equality" {
    const test_cases = [_]struct {
        a: []const u8,
        b: []const u8,
        equal: bool,
    }{
        .{ .a = "{\"a\":1,\"b\":2}", .b = "{\"b\":2,\"a\":1}", .equal = true },
        .{ .a = "[1,2,3]", .b = "[1,2,3]", .equal = true },
        .{ .a = "{\"a\":1}", .b = "{\"a\":2}", .equal = false },
        .{ .a = "[1,2,3]", .b = "[3,2,1]", .equal = false },
    };
    
    for (test_cases) |tc| {
        const result = simple.jsonEquals(tc.a, tc.b);
        try testing.expectEqual(tc.equal, result);
    }
}

test "getCapabilities returns valid hardware info" {
    const caps = simple.getCapabilities();
    
    // Basic sanity checks
    try testing.expect(caps.cpu_count >= 1);
    try testing.expect(caps.cache_line_size >= 32);
    try testing.expect(caps.cache_line_size <= 256);
}

test "performance: small input latency" {
    const allocator = testing.allocator;
    const input = "{\"small\":\"json\"}";
    
    const start = std.time.nanoTimestamp();
    const result = try simple.minify(allocator, input);
    const end = std.time.nanoTimestamp();
    defer allocator.free(result);
    
    const duration_ns = @as(u64, @intCast(end - start));
    const duration_us = duration_ns / 1000;
    
    // Small inputs should process in under 10 microseconds
    try testing.expect(duration_us < 10);
}

test "memory: no leaks in normal operation" {
    // This test will be checked by running with valgrind or similar
    const allocator = testing.allocator;
    
    // Multiple allocations and frees
    for (0..100) |_| {
        const result = try simple.minify(allocator, "{\"test\":true}");
        allocator.free(result);
    }
}

test "thread safety: concurrent minification" {
    // Note: Simple API functions are thread-safe with different allocators
    const thread_count = 4;
    var threads: [thread_count]std.Thread = undefined;
    
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, struct {
            fn worker() !void {
                var gpa = std.heap.GeneralPurposeAllocator(.{}){};
                defer _ = gpa.deinit();
                const allocator = gpa.allocator();
                
                for (0..100) |_| {
                    const result = try simple.minify(allocator, "{\"thread\":\"test\"}");
                    defer allocator.free(result);
                    
                    try testing.expectEqualStrings("{\"thread\":\"test\"}", result);
                }
            }
        }.worker, .{});
    }
    
    for (threads) |thread| {
        thread.join();
    }
}