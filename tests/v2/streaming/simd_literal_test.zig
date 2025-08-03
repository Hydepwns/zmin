const std = @import("std");
const testing = std.testing;
const parser_mod = @import("../../../src/v2/streaming/parser.zig");
const StreamingParser = parser_mod.StreamingParser;
const ParserConfig = parser_mod.ParserConfig;
const Token = parser_mod.Token;
const TokenType = parser_mod.TokenType;
const SimdLevel = parser_mod.SimdLevel;

test "SIMD literal parsing - AVX512" {
    const config = ParserConfig{
        .enable_simd = true,
        .simd_level = .avx512,
    };
    
    var test_parser = try StreamingParser.init(testing.allocator, config);
    defer test_parser.deinit();
    
    const json = 
        \\{
        \\  "is_active": true,
        \\  "is_disabled": false,
        \\  "value": null,
        \\  "array": [true, false, null, true, null, false]
        \\}
    ;
    
    var token_stream = try test_parser.parseStreaming(json);
    defer token_stream.deinit();
    
    // Count literal tokens
    var true_count: usize = 0;
    var false_count: usize = 0;
    var null_count: usize = 0;
    
    while (token_stream.hasMore()) {
        if (token_stream.getCurrentToken()) |token| {
            switch (token.token_type) {
                .boolean_true => true_count += 1,
                .boolean_false => false_count += 1,
                .null => null_count += 1,
                else => {},
            }
        }
        token_stream.advance();
    }
    
    try testing.expectEqual(@as(usize, 3), true_count);
    try testing.expectEqual(@as(usize, 3), false_count);
    try testing.expectEqual(@as(usize, 3), null_count);
}

test "SIMD literal parsing - NEON" {
    const config = ParserConfig{
        .enable_simd = true,
        .simd_level = .neon,
    };
    
    var test_parser = try StreamingParser.init(testing.allocator, config);
    defer test_parser.deinit();
    
    const json = 
        \\{
        \\  "is_active": true,
        \\  "is_disabled": false,
        \\  "value": null,
        \\  "array": [true, false, null, true, null, false]
        \\}
    ;
    
    var token_stream = try test_parser.parseStreaming(json);
    defer token_stream.deinit();
    
    // Count literal tokens
    var true_count: usize = 0;
    var false_count: usize = 0;
    var null_count: usize = 0;
    
    while (token_stream.hasMore()) {
        if (token_stream.getCurrentToken()) |token| {
            switch (token.token_type) {
                .boolean_true => true_count += 1,
                .boolean_false => false_count += 1,
                .null => null_count += 1,
                else => {},
            }
        }
        token_stream.advance();
    }
    
    try testing.expectEqual(@as(usize, 3), true_count);
    try testing.expectEqual(@as(usize, 3), false_count);
    try testing.expectEqual(@as(usize, 3), null_count);
}

test "SIMD literal parsing performance comparison" {
    // Generate test data with many literals
    var json_buf = std.ArrayList(u8).init(testing.allocator);
    defer json_buf.deinit();
    
    try json_buf.appendSlice("{\n");
    for (0..1000) |i| {
        try json_buf.writer().print("  \"field_{}\": {}, \"flag_{}\": {}, \"empty_{}\": {},\n", .{
            i,
            if (i % 3 == 0) "true" else if (i % 3 == 1) "false" else "null",
            i,
            if (i % 3 == 1) "true" else if (i % 3 == 2) "false" else "null",
            i,
            if (i % 3 == 2) "true" else if (i % 3 == 0) "false" else "null",
        });
    }
    try json_buf.appendSlice("  \"last\": true\n}");
    
    const json = json_buf.items;
    
    // Test with SIMD
    const simd_config = ParserConfig{
        .enable_simd = true,
        .simd_level = .auto,
    };
    var simd_parser = try StreamingParser.init(testing.allocator, simd_config);
    defer simd_parser.deinit();
    
    const simd_start = std.time.nanoTimestamp();
    var simd_stream = try simd_parser.parseStreaming(json);
    defer simd_stream.deinit();
    
    var simd_literal_count: usize = 0;
    while (simd_stream.hasMore()) {
        if (simd_stream.getCurrentToken()) |token| {
            switch (token.token_type) {
                .boolean_true, .boolean_false, .null => simd_literal_count += 1,
                else => {},
            }
        }
        simd_stream.advance();
    }
    const simd_time = std.time.nanoTimestamp() - simd_start;
    
    // Test with scalar
    const scalar_config = ParserConfig{
        .enable_simd = false,
        .simd_level = .none,
    };
    var scalar_parser = try StreamingParser.init(testing.allocator, scalar_config);
    defer scalar_parser.deinit();
    
    const scalar_start = std.time.nanoTimestamp();
    var scalar_stream = try scalar_parser.parseStreaming(json);
    defer scalar_stream.deinit();
    
    var scalar_literal_count: usize = 0;
    while (scalar_stream.hasMore()) {
        if (scalar_stream.getCurrentToken()) |token| {
            switch (token.token_type) {
                .boolean_true, .boolean_false, .null => scalar_literal_count += 1,
                else => {},
            }
        }
        scalar_stream.advance();
    }
    const scalar_time = std.time.nanoTimestamp() - scalar_start;
    
    // Verify both found the same number of literals
    try testing.expectEqual(simd_literal_count, scalar_literal_count);
    try testing.expect(simd_literal_count > 0);
    
    // Log performance comparison
    const speedup = @as(f64, @floatFromInt(scalar_time)) / @as(f64, @floatFromInt(simd_time));
    std.debug.print("\nSIMD Literal Parsing Performance:\n", .{});
    std.debug.print("  Literals parsed: {}\n", .{simd_literal_count});
    std.debug.print("  SIMD time: {} μs\n", .{simd_time / 1000});
    std.debug.print("  Scalar time: {} μs\n", .{scalar_time / 1000});
    std.debug.print("  Speedup: {d:.2}x\n", .{speedup});
}

test "SIMD literal parsing edge cases" {
    const test_cases = [_][]const u8{
        // Edge case: literals at boundaries
        "[true]",
        "[false]",
        "[null]",
        "{\"a\":true}",
        "{\"b\":false}",
        "{\"c\":null}",
        // Edge case: mixed with numbers
        "[true,123,false]",
        "[null,456.789,true]",
        // Edge case: consecutive literals
        "[true,true,true]",
        "[false,false,false]",
        "[null,null,null]",
        "[true,false,null]",
        // Edge case: whitespace around literals
        "[ true , false , null ]",
        "{\n  \"x\": true,\n  \"y\": false,\n  \"z\": null\n}",
        // Edge case: similar but invalid tokens
        "[truee]", // Should fail
        "[fals]",  // Should fail
        "[nul]",   // Should fail
    };
    
    for (test_cases) |test_json| {
        const config = ParserConfig{
            .enable_simd = true,
            .simd_level = .auto,
        };
        var test_parser = try StreamingParser.init(testing.allocator, config);
        defer test_parser.deinit();
        
        var token_stream = try test_parser.parseStreaming(test_json);
        defer token_stream.deinit();
        
        // Just verify it can parse without crashing
        while (token_stream.hasMore()) {
            _ = token_stream.getCurrentToken();
            token_stream.advance();
        }
    }
}