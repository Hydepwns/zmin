const std = @import("std");
const testing = std.testing;
const v2 = @import("src").v2;
const TokenStream = v2.TokenStream;
const Token = v2.Token;
const TokenType = v2.TokenType;
const MemoryPool = v2.MemoryPool;

test "TokenStream - basic token operations" {
    const allocator = testing.allocator;
    
    const input = "{\"test\":123}";
    var stream = TokenStream.init(allocator, input);
    defer stream.deinit();
    
    // Add tokens
    try stream.addToken(.{
        .token_type = .object_start,
        .start = 0,
        .end = 1,
    });
    
    try stream.addToken(.{
        .token_type = .string,
        .start = 1,
        .end = 7,
    });
    
    try stream.addToken(.{
        .token_type = .colon,
        .start = 7,
        .end = 8,
    });
    
    try stream.addToken(.{
        .token_type = .number,
        .start = 8,
        .end = 11,
    });
    
    try stream.addToken(.{
        .token_type = .object_end,
        .start = 11,
        .end = 12,
    });
    
    // Test getTokenCount
    try testing.expectEqual(@as(usize, 5), stream.getTokenCount());
    
    // Test getToken
    const first_token = stream.getToken(0).?;
    try testing.expectEqual(TokenType.object_start, first_token.token_type);
    try testing.expectEqual(@as(usize, 0), first_token.start);
    try testing.expectEqual(@as(usize, 1), first_token.end);
    
    const string_token = stream.getToken(1).?;
    try testing.expectEqual(TokenType.string, string_token.token_type);
    const string_value = input[string_token.start..string_token.end];
    try testing.expectEqualStrings("\"test\"", string_value);
    
    // Test out of bounds
    try testing.expect(stream.getToken(10) == null);
}

test "MemoryPool - allocation and deallocation" {
    const allocator = testing.allocator;
    
    var pool = MemoryPool.init(allocator, 1024);
    defer pool.deinit();
    
    // Test initial state
    try testing.expectEqual(@as(usize, 1024), pool.size);
    
    // Allocate some memory
    const ptr1 = try pool.allocate(100);
    try testing.expect(ptr1.len == 100);
    
    // Allocate more
    const ptr2 = try pool.allocate(200);
    try testing.expect(ptr2.len == 200);
    
    // Reset pool
    pool.reset();
    try testing.expectEqual(@as(usize, 0), pool.current_pos);
}

test "MemoryPool - basic allocation" {
    const allocator = testing.allocator;
    
    var pool = MemoryPool.init(allocator, 1024);
    defer pool.deinit();
    
    // Allocate some bytes
    const bytes = try pool.allocate(100);
    try testing.expect(bytes.len == 100);
    
    // Allocate more
    const more_bytes = try pool.allocate(200);
    try testing.expect(more_bytes.len == 200);
    
    // Check they don't overlap
    try testing.expect(@intFromPtr(bytes.ptr) != @intFromPtr(more_bytes.ptr));
}

test "MemoryPool - large allocation handling" {
    const allocator = testing.allocator;
    
    var pool = MemoryPool.init(allocator, 128); // Small pool
    defer pool.deinit();
    
    // Allocate more than pool size (should still work, using direct allocation)
    const result = try pool.allocate(256);
    try testing.expect(result.len == 256);
    
    // Allocate within pool size
    const result2 = try pool.allocate(100);
    try testing.expect(result2.len == 100);
}

test "TokenStream - iterator pattern" {
    const allocator = testing.allocator;
    
    const input = "[1,2,3]";
    var stream = TokenStream.init(allocator, input);
    defer stream.deinit();
    
    // Add array tokens
    try stream.addToken(.{ .token_type = .array_start, .start = 0, .end = 1 });
    try stream.addToken(.{ .token_type = .number, .start = 1, .end = 2 });
    try stream.addToken(.{ .token_type = .comma, .start = 2, .end = 3 });
    try stream.addToken(.{ .token_type = .number, .start = 3, .end = 4 });
    try stream.addToken(.{ .token_type = .comma, .start = 4, .end = 5 });
    try stream.addToken(.{ .token_type = .number, .start = 5, .end = 6 });
    try stream.addToken(.{ .token_type = .array_end, .start = 6, .end = 7 });
    
    // Count specific token types
    var number_count: usize = 0;
    var i: usize = 0;
    while (i < stream.getTokenCount()) : (i += 1) {
        const token = stream.getToken(i).?;
        if (token.token_type == .number) {
            number_count += 1;
        }
    }
    
    try testing.expectEqual(@as(usize, 3), number_count);
}

test "Token - value extraction" {
    const input = "{\"key\":\"value\",\"num\":42,\"bool\":true}";
    
    // String token
    const string_token = Token{
        .token_type = .string,
        .start = 7,
        .end = 14,
    };
    const string_value = input[string_token.start..string_token.end];
    try testing.expectEqualStrings("\"value\"", string_value);
    
    // Number token
    const number_token = Token{
        .token_type = .number,
        .start = 21,
        .end = 23,
    };
    const number_value = input[number_token.start..number_token.end];
    try testing.expectEqualStrings("42", number_value);
    
    // Boolean token
    const bool_token = Token{
        .token_type = .true_literal,
        .start = 32,
        .end = 36,
    };
    const bool_value = input[bool_token.start..bool_token.end];
    try testing.expectEqualStrings("true", bool_value);
}

test "TokenStream - nested structure navigation" {
    const allocator = testing.allocator;
    
    const input = "{\"a\":{\"b\":[1,2]}}";
    var stream = TokenStream.init(allocator, input);
    defer stream.deinit();
    
    // Build token structure
    try stream.addToken(.{ .token_type = .object_start, .start = 0, .end = 1 });
    try stream.addToken(.{ .token_type = .string, .start = 1, .end = 4 });
    try stream.addToken(.{ .token_type = .colon, .start = 4, .end = 5 });
    try stream.addToken(.{ .token_type = .object_start, .start = 5, .end = 6 });
    try stream.addToken(.{ .token_type = .string, .start = 6, .end = 9 });
    try stream.addToken(.{ .token_type = .colon, .start = 9, .end = 10 });
    try stream.addToken(.{ .token_type = .array_start, .start = 10, .end = 11 });
    try stream.addToken(.{ .token_type = .number, .start = 11, .end = 12 });
    try stream.addToken(.{ .token_type = .comma, .start = 12, .end = 13 });
    try stream.addToken(.{ .token_type = .number, .start = 13, .end = 14 });
    try stream.addToken(.{ .token_type = .array_end, .start = 14, .end = 15 });
    try stream.addToken(.{ .token_type = .object_end, .start = 15, .end = 16 });
    try stream.addToken(.{ .token_type = .object_end, .start = 16, .end = 17 });
    
    // Test navigation through structure
    var depth: i32 = 0;
    var max_depth: i32 = 0;
    
    var i: usize = 0;
    while (i < stream.getTokenCount()) : (i += 1) {
        const token = stream.getToken(i).?;
        switch (token.token_type) {
            .object_start, .array_start => {
                depth += 1;
                if (depth > max_depth) max_depth = depth;
            },
            .object_end, .array_end => {
                depth -= 1;
            },
            else => {},
        }
    }
    
    try testing.expectEqual(@as(i32, 3), max_depth); // Maximum nesting depth
    try testing.expectEqual(@as(i32, 0), depth); // Should be balanced
}

test "MemoryPool - stress test with many small allocations" {
    const allocator = testing.allocator;
    
    var pool = MemoryPool.init(allocator, 4096);
    defer pool.deinit();
    
    // Make many small allocations
    var total_allocated: usize = 0;
    var allocation_count: usize = 0;
    
    while (total_allocated < 3000) {
        const size = 10 + (allocation_count % 50);
        const ptr = pool.alloc(u8, size) catch break;
        
        // Write pattern to verify memory
        for (ptr) |*byte| {
            byte.* = @as(u8, @truncate(allocation_count));
        }
        
        total_allocated += size;
        allocation_count += 1;
    }
    
    try testing.expect(allocation_count > 20); // Should fit many allocations
    try testing.expect(total_allocated > 2000); // Should use most of the pool
}

test "TokenType - comprehensive coverage" {
    // Ensure all token types are handled
    const token_types = [_]TokenType{
        .object_start,
        .object_end,
        .array_start,
        .array_end,
        .string,
        .number,
        .true_literal,
        .false_literal,
        .null_literal,
        .colon,
        .comma,
        .whitespace,
        .error_token,
    };
    
    // Test that each type has a unique value
    var seen = std.AutoHashMap(u8, void).init(testing.allocator);
    defer seen.deinit();
    
    for (token_types) |token_type| {
        const value = @intFromEnum(token_type);
        try testing.expect(!seen.contains(value));
        try seen.put(value, {});
    }
}