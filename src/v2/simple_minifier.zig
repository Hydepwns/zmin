const std = @import("std");
const Allocator = std.mem.Allocator;
const v2 = @import("mod.zig");

/// Simple, working minifier for v2 foundation
pub fn minifySimple(allocator: Allocator, input: []const u8) ![]u8 {
    // Create parser
    var parser = try v2.StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    // Parse input
    const token_stream = try parser.parseStreaming(input);
    defer token_stream.tokens.deinit();
    
    // Create output buffer
    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    
    // Minify by processing tokens
    var pos: usize = 0;
    while (pos < token_stream.getTokenCount()) : (pos += 1) {
        const token = token_stream.getToken(pos).?;
        
        switch (token.token_type) {
            .whitespace => {
                // Skip whitespace for minification
                continue;
            },
            .comment => {
                // Skip comments for minification
                continue;
            },
            .object_start => try output_buffer.append('{'),
            .object_end => try output_buffer.append('}'),
            .array_start => try output_buffer.append('['),
            .array_end => try output_buffer.append(']'),
            .comma => try output_buffer.append(','),
            .colon => try output_buffer.append(':'),
            .string, .number, .boolean_true, .boolean_false, .null => {
                // Copy value tokens as-is
                const value = input[token.start..token.end];
                try output_buffer.appendSlice(value);
            },
            else => {
                // Handle other tokens
                const value = input[token.start..token.end];
                try output_buffer.appendSlice(value);
            },
        }
    }
    
    return output_buffer.toOwnedSlice();
}

test "simple minifier - basic JSON" {
    const allocator = std.testing.allocator;
    
    const input = "{ \"name\" : \"test\" , \"value\" : 42 }";
    const output = try minifySimple(allocator, input);
    defer allocator.free(output);
    
    try std.testing.expectEqualStrings("{\"name\":\"test\",\"value\":42}", output);
}

test "simple minifier - nested objects" {
    const allocator = std.testing.allocator;
    
    const input = "{ \"user\" : { \"name\" : \"Alice\" , \"age\" : 30 } }";
    const output = try minifySimple(allocator, input);
    defer allocator.free(output);
    
    try std.testing.expectEqualStrings("{\"user\":{\"name\":\"Alice\",\"age\":30}}", output);
}

test "simple minifier - arrays" {
    const allocator = std.testing.allocator;
    
    const input = "[ 1 , 2 , 3 , \"test\" , true , null ]";
    const output = try minifySimple(allocator, input);
    defer allocator.free(output);
    
    try std.testing.expectEqualStrings("[1,2,3,\"test\",true,null]", output);
}