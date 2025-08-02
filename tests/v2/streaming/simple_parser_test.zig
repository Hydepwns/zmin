const std = @import("std");
const testing = std.testing;
const v2 = @import("src").v2;

test "v2 StreamingParser - basic initialization" {
    const allocator = testing.allocator;
    
    var parser = try v2.StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    // Basic structure test
    try testing.expect(parser.config.enable_simd == true);
    try testing.expect(parser.config.memory_pool_size == 1024 * 1024);
}

test "v2 TokenStream - basic operations" {
    const allocator = testing.allocator;
    
    const input = "{\"test\":123}";
    var stream = v2.TokenStream.init(allocator, input);
    defer stream.deinit();
    
    // Add a token
    try stream.addToken(.{
        .token_type = .object_start,
        .start = 0,
        .end = 1,
        .line = 1,
        .column = 1,
    });
    
    try testing.expectEqual(@as(usize, 1), stream.getTokenCount());
    
    const token = stream.getToken(0).?;
    try testing.expectEqual(v2.TokenType.object_start, token.token_type);
}

test "v2 MemoryPool - basic allocation" {
    const allocator = testing.allocator;
    
    var pool = v2.MemoryPool.init(allocator, 1024);
    defer pool.deinit();
    
    const bytes = try pool.allocate(100);
    try testing.expect(bytes.len == 100);
    
    pool.reset();
    try testing.expectEqual(@as(usize, 0), pool.current_pos);
}

test "v2 convenience functions" {
    const allocator = testing.allocator;
    
    const input = "{ \"name\" : \"test\" }";
    const output = try v2.minify(allocator, input);
    defer allocator.free(output);
    
    try testing.expect(output.len > 0);
    try testing.expect(output.len < input.len);
}