const std = @import("std");
const testing = std.testing;
const StreamingParser = @import("../../../src/v2/streaming/parser.zig").StreamingParser;
const ParserConfig = @import("../../../src/v2/streaming/parser.zig").ParserConfig;
const Token = @import("../../../src/v2/streaming/parser.zig").Token;
const TokenType = @import("../../../src/v2/streaming/parser.zig").TokenType;
const SimdLevel = @import("../../../src/v2/streaming/parser.zig").SimdLevel;

test "NEON parser basic structural tokens" {
    var config = ParserConfig{
        .enable_simd = true,
        .simd_level = .neon,
    };
    
    var parser = try StreamingParser.init(std.testing.allocator, config);
    defer parser.deinit();
    
    const json = 
        \\{
        \\  "name": "test",
        \\  "values": [1, 2, 3],
        \\  "nested": {
        \\    "flag": true,
        \\    "empty": null
        \\  }
        \\}
    ;
    
    var tokens = std.ArrayList(Token).init(std.testing.allocator);
    defer tokens.deinit();
    
    const callback = struct {
        fn cb(ctx: *anyopaque, token: Token) !void {
            const list = @as(*std.ArrayList(Token), @ptrCast(@alignCast(ctx)));
            try list.append(token);
        }
    }.cb;
    
    try parser.parseChunk(json, callback, &tokens);
    
    // Verify we got the expected structural tokens
    var structural_count: usize = 0;
    for (tokens.items) |token| {
        switch (token.token_type) {
            .object_start, .object_end, .array_start, .array_end, .comma, .colon => {
                structural_count += 1;
            },
            else => {},
        }
    }
    
    // Should have: 2 {, 2 }, 1 [, 1 ], 5 commas, 5 colons = 16 structural tokens
    try testing.expect(structural_count >= 16);
}

test "NEON parser string optimization" {
    var config = ParserConfig{
        .enable_simd = true,
        .simd_level = .neon,
    };
    
    var parser = try StreamingParser.init(std.testing.allocator, config);
    defer parser.deinit();
    
    // Test with strings that span multiple 16-byte chunks
    const json = 
        \\{
        \\  "short": "abc",
        \\  "medium": "this is a medium length string",
        \\  "long": "this is a very long string that spans multiple NEON vector chunks to test the optimization",
        \\  "escaped": "string with \"quotes\" and \\ backslashes"
        \\}
    ;
    
    var tokens = std.ArrayList(Token).init(std.testing.allocator);
    defer tokens.deinit();
    
    const callback = struct {
        fn cb(ctx: *anyopaque, token: Token) !void {
            const list = @as(*std.ArrayList(Token), @ptrCast(@alignCast(ctx)));
            try list.append(token);
        }
    }.cb;
    
    try parser.parseChunk(json, callback, &tokens);
    
    // Count string tokens
    var string_count: usize = 0;
    for (tokens.items) |token| {
        if (token.token_type == .string) {
            string_count += 1;
        }
    }
    
    // Should have 8 strings (4 keys + 4 values)
    try testing.expectEqual(@as(usize, 8), string_count);
}

test "NEON parser number optimization" {
    var config = ParserConfig{
        .enable_simd = true,
        .simd_level = .neon,
    };
    
    var parser = try StreamingParser.init(std.testing.allocator, config);
    defer parser.deinit();
    
    // Test various number formats
    const json = 
        \\{
        \\  "integers": [123, -456, 0, 999999999],
        \\  "floats": [3.14, -2.718, 0.001, 123.456],
        \\  "scientific": [1.23e4, -5.67e-8, 9.87E+10]
        \\}
    ;
    
    var tokens = std.ArrayList(Token).init(std.testing.allocator);
    defer tokens.deinit();
    
    const callback = struct {
        fn cb(ctx: *anyopaque, token: Token) !void {
            const list = @as(*std.ArrayList(Token), @ptrCast(@alignCast(ctx)));
            try list.append(token);
        }
    }.cb;
    
    try parser.parseChunk(json, callback, &tokens);
    
    // Count number tokens
    var number_count: usize = 0;
    for (tokens.items) |token| {
        if (token.token_type == .number) {
            number_count += 1;
        }
    }
    
    // Should have 11 numbers total
    try testing.expectEqual(@as(usize, 11), number_count);
}

test "NEON parser performance comparison" {
    // Test NEON vs scalar performance
    var allocator = std.testing.allocator;
    
    // Generate a larger JSON for performance testing
    var json_buf = std.ArrayList(u8).init(allocator);
    defer json_buf.deinit();
    
    try json_buf.appendSlice("{\n");
    for (0..100) |i| {
        try json_buf.writer().print("  \"field_{}\": \"value_{}_with_some_longer_content_to_test_NEON\",\n", .{ i, i });
    }
    try json_buf.appendSlice("  \"last\": true\n}");
    
    const json = json_buf.items;
    
    // Test with NEON
    var neon_config = ParserConfig{
        .enable_simd = true,
        .simd_level = .neon,
    };
    var neon_parser = try StreamingParser.init(allocator, neon_config);
    defer neon_parser.deinit();
    
    var neon_tokens = std.ArrayList(Token).init(allocator);
    defer neon_tokens.deinit();
    
    const callback = struct {
        fn cb(ctx: *anyopaque, token: Token) !void {
            const list = @as(*std.ArrayList(Token), @ptrCast(@alignCast(ctx)));
            try list.append(token);
        }
    }.cb;
    
    const neon_start = std.time.nanoTimestamp();
    try neon_parser.parseChunk(json, callback, &neon_tokens);
    const neon_time = std.time.nanoTimestamp() - neon_start;
    
    // Test with scalar
    var scalar_config = ParserConfig{
        .enable_simd = false,
        .simd_level = .none,
    };
    var scalar_parser = try StreamingParser.init(allocator, scalar_config);
    defer scalar_parser.deinit();
    
    var scalar_tokens = std.ArrayList(Token).init(allocator);
    defer scalar_tokens.deinit();
    
    const scalar_start = std.time.nanoTimestamp();
    try scalar_parser.parseChunk(json, callback, &scalar_tokens);
    const scalar_time = std.time.nanoTimestamp() - scalar_start;
    
    // Verify both parsers found the same number of tokens
    try testing.expectEqual(neon_tokens.items.len, scalar_tokens.items.len);
    
    // Log performance comparison
    const speedup = @as(f64, @floatFromInt(scalar_time)) / @as(f64, @floatFromInt(neon_time));
    std.debug.print("\nNEON Parser Performance:\n", .{});
    std.debug.print("  NEON time: {} ns\n", .{neon_time});
    std.debug.print("  Scalar time: {} ns\n", .{scalar_time});
    std.debug.print("  Speedup: {d:.2}x\n", .{speedup});
}