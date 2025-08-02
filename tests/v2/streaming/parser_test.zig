const std = @import("std");
const testing = std.testing;
const v2 = @import("src").v2;
const StreamingParser = v2.StreamingParser;
const ParserConfig = v2.ParserConfig;
const TokenType = v2.TokenType;

test "StreamingParser.init - creates parser with default config" {
    const allocator = testing.allocator;
    const config = ParserConfig{};
    
    var parser = try StreamingParser.init(allocator, config);
    defer parser.deinit();
    
    try testing.expect(parser.config.chunk_size == 256 * 1024);
    try testing.expect(parser.config.enable_simd == true);
    try testing.expect(parser.config.memory_pool_size == 1024 * 1024);
}

test "StreamingParser.init - creates parser with custom config" {
    const allocator = testing.allocator;
    const config = ParserConfig{
        .chunk_size = 128 * 1024,
        .enable_simd = false,
        .memory_pool_size = 2 * 1024 * 1024,
    };
    
    var parser = try StreamingParser.init(allocator, config);
    defer parser.deinit();
    
    try testing.expectEqual(@as(usize, 128 * 1024), parser.config.chunk_size);
    try testing.expectEqual(false, parser.config.enable_simd);
    try testing.expectEqual(@as(usize, 2 * 1024 * 1024), parser.config.memory_pool_size);
}

test "StreamingParser.parseStreaming - empty JSON object" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "{}";
    const token_stream = try parser.parseStreaming(input);
    
    try testing.expectEqual(@as(usize, 2), token_stream.getTokenCount());
    
    const first_token = token_stream.getToken(0).?;
    try testing.expectEqual(TokenType.object_start, first_token.token_type);
    try testing.expectEqual(@as(usize, 0), first_token.start);
    try testing.expectEqual(@as(usize, 1), first_token.end);
    
    const second_token = token_stream.getToken(1).?;
    try testing.expectEqual(TokenType.object_end, second_token.token_type);
    try testing.expectEqual(@as(usize, 1), second_token.start);
    try testing.expectEqual(@as(usize, 2), second_token.end);
}

test "StreamingParser.parseStreaming - empty JSON array" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "[]";
    const token_stream = try parser.parseStreaming(input);
    
    try testing.expectEqual(@as(usize, 2), token_stream.getTokenCount());
    
    const first_token = token_stream.getToken(0).?;
    try testing.expectEqual(TokenType.array_start, first_token.token_type);
    
    const second_token = token_stream.getToken(1).?;
    try testing.expectEqual(TokenType.array_end, second_token.token_type);
}

test "StreamingParser.parseStreaming - simple object with string" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "{\"name\":\"test\"}";
    const token_stream = try parser.parseStreaming(input);
    
    // Expected tokens: { "name" : "test" }
    try testing.expectEqual(@as(usize, 5), token_stream.getTokenCount());
    
    var i: usize = 0;
    try testing.expectEqual(TokenType.object_start, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.string, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.colon, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.string, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.object_end, token_stream.getToken(i).?.token_type);
}

test "StreamingParser.parseStreaming - nested objects" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "{\"outer\":{\"inner\":true}}";
    const token_stream = try parser.parseStreaming(input);
    
    // Expected tokens: { "outer" : { "inner" : true } }
    try testing.expectEqual(@as(usize, 8), token_stream.getTokenCount());
    
    var i: usize = 0;
    try testing.expectEqual(TokenType.object_start, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.string, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.colon, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.object_start, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.string, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.colon, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.true_literal, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.object_end, token_stream.getToken(i).?.token_type);
}

test "StreamingParser.parseStreaming - array with mixed types" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "[123, \"hello\", true, null, 45.67]";
    const token_stream = try parser.parseStreaming(input);
    
    // Expected tokens: [ 123 , "hello" , true , null , 45.67 ]
    try testing.expectEqual(@as(usize, 10), token_stream.getTokenCount());
    
    var i: usize = 0;
    try testing.expectEqual(TokenType.array_start, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.number, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.comma, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.string, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.comma, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.true_literal, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.comma, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.null_literal, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.comma, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.number, token_stream.getToken(i).?.token_type);
}

test "StreamingParser.parseStreaming - whitespace handling" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "  {  \"key\"  :  \"value\"  }  ";
    const token_stream = try parser.parseStreaming(input);
    
    // Whitespace should be ignored, only structural tokens
    try testing.expectEqual(@as(usize, 5), token_stream.getTokenCount());
    
    var i: usize = 0;
    try testing.expectEqual(TokenType.object_start, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.string, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.colon, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.string, token_stream.getToken(i).?.token_type);
    i += 1;
    try testing.expectEqual(TokenType.object_end, token_stream.getToken(i).?.token_type);
}

test "StreamingParser.parseStreaming - escaped characters in strings" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "{\"escaped\":\"line\\nbreak\\ttab\\\"\"}";
    const token_stream = try parser.parseStreaming(input);
    
    try testing.expectEqual(@as(usize, 5), token_stream.getTokenCount());
    
    const value_token = token_stream.getToken(3).?;
    try testing.expectEqual(TokenType.string, value_token.token_type);
    
    const value = input[value_token.start..value_token.end];
    try testing.expectEqualStrings("\"line\\nbreak\\ttab\\\"\"", value);
}

test "StreamingParser.parseStreaming - large numbers" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "[123456789012345, -987654321098765, 3.14159265359e10]";
    const token_stream = try parser.parseStreaming(input);
    
    try testing.expectEqual(@as(usize, 6), token_stream.getTokenCount());
    
    // Check that all numbers are recognized
    try testing.expectEqual(TokenType.number, token_stream.getToken(1).?.token_type);
    try testing.expectEqual(TokenType.number, token_stream.getToken(3).?.token_type);
    try testing.expectEqual(TokenType.number, token_stream.getToken(5).?.token_type);
}

test "StreamingParser.parseStreaming - unicode strings" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "{\"emoji\":\"🚀\",\"chinese\":\"你好\",\"arabic\":\"مرحبا\"}";
    const token_stream = try parser.parseStreaming(input);
    
    // Should handle UTF-8 encoded strings correctly
    try testing.expectEqual(@as(usize, 11), token_stream.getTokenCount());
    
    // Verify all string tokens are recognized
    try testing.expectEqual(TokenType.string, token_stream.getToken(1).?.token_type);
    try testing.expectEqual(TokenType.string, token_stream.getToken(3).?.token_type);
    try testing.expectEqual(TokenType.string, token_stream.getToken(5).?.token_type);
    try testing.expectEqual(TokenType.string, token_stream.getToken(7).?.token_type);
    try testing.expectEqual(TokenType.string, token_stream.getToken(9).?.token_type);
}

test "StreamingParser.reset - clears parser state" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    // Parse first JSON
    const input1 = "{\"first\":true}";
    _ = try parser.parseStreaming(input1);
    
    // Reset parser
    parser.reset();
    
    // Parse second JSON
    const input2 = "{\"second\":false}";
    const token_stream = try parser.parseStreaming(input2);
    
    // Should only have tokens from second parse
    try testing.expectEqual(@as(usize, 5), token_stream.getTokenCount());
    
    const key_token = token_stream.getToken(1).?;
    const key = input2[key_token.start..key_token.end];
    try testing.expectEqualStrings("\"second\"", key);
}

test "StreamingParser.benchmarkParsing - performance measurement" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "{\"data\":[1,2,3,4,5],\"nested\":{\"value\":true}}";
    
    const start = std.time.milliTimestamp();
    _ = try parser.benchmarkParsing(input, 1000);
    const end = std.time.milliTimestamp();
    
    // Should complete reasonably fast
    try testing.expect((end - start) < 1000); // Less than 1 second for 1000 iterations
}

test "StreamingParser - SIMD optimization paths" {
    const allocator = testing.allocator;
    
    // Test with SIMD enabled
    var parser_simd = try StreamingParser.init(allocator, .{ .enable_simd = true });
    defer parser_simd.deinit();
    
    // Test with SIMD disabled
    var parser_scalar = try StreamingParser.init(allocator, .{ .enable_simd = false });
    defer parser_scalar.deinit();
    
    const input = "{\"test\":\"value\",\"array\":[1,2,3]}";
    
    const tokens_simd = try parser_simd.parseStreaming(input);
    const tokens_scalar = try parser_scalar.parseStreaming(input);
    
    // Both should produce same results
    try testing.expectEqual(tokens_simd.getTokenCount(), tokens_scalar.getTokenCount());
}

test "StreamingParser - error handling for invalid JSON" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    // Missing closing brace
    const invalid1 = "{\"unclosed\":true";
    const result1 = parser.parseStreaming(invalid1);
    try testing.expectError(error.UnexpectedEndOfInput, result1);
    
    // Invalid token
    const invalid2 = "{\"key\":undefined}";
    const result2 = parser.parseStreaming(invalid2);
    try testing.expectError(error.InvalidToken, result2);
    
    // Trailing comma
    const invalid3 = "[1,2,3,]";
    const result3 = parser.parseStreaming(invalid3);
    try testing.expectError(error.InvalidToken, result3);
}

test "StreamingParser - memory pool usage" {
    const allocator = testing.allocator;
    var parser = try StreamingParser.init(allocator, .{
        .memory_pool_size = 1024, // Small pool to test allocation
    });
    defer parser.deinit();
    
    // Parse multiple times to test pool reuse
    const input = "{\"key\":\"value\"}";
    
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        parser.reset();
        _ = try parser.parseStreaming(input);
    }
    
    // Should handle multiple parses with small pool
    try testing.expect(true);
}