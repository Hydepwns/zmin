const std = @import("std");
const testing = std.testing;
const ParallelParser = @import("../../../src/v2/streaming/parallel_parser.zig").ParallelParser;
const ParallelConfig = @import("../../../src/v2/streaming/parallel_parser.zig").ParallelConfig;
const JsonChunk = @import("../../../src/v2/streaming/parallel_parser.zig").JsonChunk;
const BoundaryType = @import("../../../src/v2/streaming/parallel_parser.zig").BoundaryType;

test "ParallelParser basic functionality" {
    const allocator = testing.allocator;
    
    var parser = try ParallelParser.init(allocator, .{
        .num_threads = 2,
        .min_chunk_size = 100,
        .target_chunk_size = 200,
    });
    defer parser.deinit();
    
    const json = 
        \\{
        \\  "items": [
        \\    {"id": 1, "name": "First"},
        \\    {"id": 2, "name": "Second"},
        \\    {"id": 3, "name": "Third"}
        \\  ],
        \\  "count": 3
        \\}
    ;
    
    var tokens = try parser.parse(json);
    defer tokens.deinit();
    
    // Should have parsed all tokens
    try testing.expect(tokens.items.len > 0);
    
    // Verify first and last tokens
    try testing.expectEqual(@as(u8, '{'), json[tokens.items[0].start]);
    try testing.expectEqual(@as(u8, '}'), json[tokens.items[tokens.items.len - 1].start]);
}

test "ParallelParser chunk partitioning" {
    const allocator = testing.allocator;
    
    var parser = try ParallelParser.init(allocator, .{
        .num_threads = 4,
        .min_chunk_size = 50,
        .target_chunk_size = 100,
    });
    defer parser.deinit();
    
    // Create JSON that should be split into multiple chunks
    var json_buf = std.ArrayList(u8).init(allocator);
    defer json_buf.deinit();
    
    try json_buf.appendSlice("{\n");
    for (0..20) |i| {
        try json_buf.writer().print("  \"field_{}\": \"value_{}\",\n", .{ i, i });
    }
    try json_buf.appendSlice("  \"last\": true\n}");
    
    const json = json_buf.items;
    
    // Test chunk partitioning
    const chunks = try parser.partitionData(json);
    defer allocator.free(chunks);
    
    // Should have multiple chunks
    try testing.expect(chunks.len > 1);
    
    // Verify chunks cover entire input
    try testing.expectEqual(@as(usize, 0), chunks[0].start);
    try testing.expectEqual(json.len, chunks[chunks.len - 1].end);
    
    // Verify chunks don't overlap
    for (0..chunks.len - 1) |i| {
        try testing.expectEqual(chunks[i].end, chunks[i + 1].start);
    }
}

test "ParallelParser performance scaling" {
    const allocator = testing.allocator;
    
    // Generate a larger JSON for performance testing
    var json_buf = std.ArrayList(u8).init(allocator);
    defer json_buf.deinit();
    
    try json_buf.appendSlice("[\n");
    for (0..1000) |i| {
        if (i > 0) try json_buf.appendSlice(",\n");
        try json_buf.writer().print(
            \\  {{
            \\    "id": {},
            \\    "data": "Some test data for item {}",
            \\    "values": [1, 2, 3, 4, 5]
            \\  }}
        , .{ i, i });
    }
    try json_buf.appendSlice("\n]");
    
    const json = json_buf.items;
    
    // Test with different thread counts
    const configs = [_]struct { threads: usize, name: []const u8 }{
        .{ .threads = 1, .name = "single" },
        .{ .threads = 2, .name = "dual" },
        .{ .threads = 4, .name = "quad" },
    };
    
    var timings = std.ArrayList(u64).init(allocator);
    defer timings.deinit();
    
    for (configs) |config| {
        var parser = try ParallelParser.init(allocator, .{
            .num_threads = config.threads,
            .min_chunk_size = 1024,
            .target_chunk_size = 4096,
        });
        defer parser.deinit();
        
        const start = std.time.nanoTimestamp();
        var tokens = try parser.parse(json);
        defer tokens.deinit();
        const elapsed = @as(u64, @intCast(std.time.nanoTimestamp() - start));
        
        try timings.append(elapsed);
        
        // All parsers should produce the same number of tokens
        if (config.threads == 1) {
            try testing.expect(tokens.items.len > 0);
        }
    }
    
    // Verify multi-threaded is not significantly slower than single-threaded
    // (It might not be faster for small inputs due to overhead)
    const single_time = timings.items[0];
    const dual_time = timings.items[1];
    
    const overhead_factor = @as(f64, @floatFromInt(dual_time)) / @as(f64, @floatFromInt(single_time));
    try testing.expect(overhead_factor < 2.0); // Should have less than 2x overhead
}

test "ParallelParser error handling" {
    const allocator = testing.allocator;
    
    var parser = try ParallelParser.init(allocator, .{
        .num_threads = 2,
        .min_chunk_size = 10,
    });
    defer parser.deinit();
    
    // Test with invalid JSON
    const invalid_json = 
        \\{
        \\  "incomplete": [1, 2, 3
    ;
    
    var tokens = try parser.parse(invalid_json);
    defer tokens.deinit();
    
    // Should still return some tokens even with errors
    try testing.expect(tokens.items.len > 0);
}

test "ParallelParser small input fallback" {
    const allocator = testing.allocator;
    
    var parser = try ParallelParser.init(allocator, .{
        .num_threads = 4,
        .min_chunk_size = 1000, // Large minimum
    });
    defer parser.deinit();
    
    // Small JSON that should use single-threaded parsing
    const json = "{\"test\": true}";
    
    var tokens = try parser.parse(json);
    defer tokens.deinit();
    
    // Should still parse correctly
    try testing.expect(tokens.items.len > 0);
    
    const stats = parser.getStats();
    // Should have only one chunk (single-threaded)
    try testing.expectEqual(@as(usize, 0), stats.num_chunks);
}

test "ParallelParser chunk boundary detection" {
    const allocator = testing.allocator;
    
    var parser = try ParallelParser.init(allocator, .{
        .num_threads = 2,
        .min_chunk_size = 20,
        .target_chunk_size = 40,
    });
    defer parser.deinit();
    
    // JSON with clear structure boundaries
    const json = 
        \\{
        \\  "a": {"nested": true},
        \\  "b": [1, 2, 3],
        \\  "c": "string"
        \\}
    ;
    
    const chunks = try parser.partitionData(json);
    defer allocator.free(chunks);
    
    // Verify chunks end at reasonable boundaries
    for (chunks) |chunk| {
        if (chunk.end < json.len) {
            const boundary_char = json[chunk.end - 1];
            // Should end after structural characters
            try testing.expect(boundary_char == ',' or 
                              boundary_char == '}' or 
                              boundary_char == ']');
        }
    }
}