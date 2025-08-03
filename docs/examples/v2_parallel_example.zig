const std = @import("std");
const v2 = @import("zmin_lib").v2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Generate test data
    const json_data = try generateLargeJson(allocator, 10_000_000); // 10MB
    defer allocator.free(json_data);

    std.debug.print("\n=== zmin v2.0 Parallel Parser Example ===\n", .{});
    std.debug.print("Input size: {} MB\n", .{json_data.len / (1024 * 1024)});

    // Test single-threaded parsing
    {
        std.debug.print("\n--- Single-threaded Parsing ---\n", .{});
        
        var parser = try v2.StreamingParser.init(allocator, .{
            .enable_simd = true,
            .simd_level = .auto,
        });
        defer parser.deinit();

        const start_time = std.time.nanoTimestamp();
        var token_stream = try parser.parseStreaming(json_data);
        defer token_stream.deinit();
        const single_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
        
        const token_count = token_stream.getTokenCount();

        const throughput_mbps = calculateThroughput(json_data.len, single_time);
        std.debug.print("Time: {} ms\n", .{single_time / 1_000_000});
        std.debug.print("Tokens: {}\n", .{token_count});
        std.debug.print("Throughput: {d:.2} MB/s\n", .{throughput_mbps});
    }

    // Test parallel parsing with different thread counts
    const thread_counts = [_]usize{ 2, 4, 8, 0 }; // 0 = auto-detect

    for (thread_counts) |num_threads| {
        std.debug.print("\n--- Parallel Parsing ({} threads) ---\n", .{
            if (num_threads == 0) try std.Thread.getCpuCount() else num_threads,
        });

        var parallel_parser = try v2.ParallelParser.init(allocator, .{
            .num_threads = num_threads,
            .min_chunk_size = 256 * 1024, // 256KB
            .target_chunk_size = 1024 * 1024, // 1MB
            .parser_config = .{
                .enable_simd = true,
                .simd_level = .auto,
            },
        });
        defer parallel_parser.deinit();

        const start_time = std.time.nanoTimestamp();
        var tokens = try parallel_parser.parse(json_data);
        defer tokens.deinit();
        const parallel_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));

        const stats = parallel_parser.getStats();
        const throughput_mbps = calculateThroughput(json_data.len, parallel_time);

        std.debug.print("Time: {} ms\n", .{parallel_time / 1_000_000});
        std.debug.print("Tokens: {}\n", .{tokens.items.len});
        std.debug.print("Throughput: {d:.2} MB/s\n", .{throughput_mbps});
        stats.print();
    }

    // Test with varying chunk sizes
    std.debug.print("\n--- Chunk Size Analysis ---\n", .{});
    const chunk_sizes = [_]usize{ 
        64 * 1024,    // 64KB
        256 * 1024,   // 256KB
        1024 * 1024,  // 1MB
        4 * 1024 * 1024, // 4MB
    };

    for (chunk_sizes) |chunk_size| {
        std.debug.print("\nChunk size: {} KB\n", .{chunk_size / 1024});

        var parallel_parser = try v2.ParallelParser.init(allocator, .{
            .num_threads = 0, // Auto-detect
            .min_chunk_size = chunk_size / 2,
            .target_chunk_size = chunk_size,
            .parser_config = .{
                .enable_simd = true,
                .simd_level = .auto,
            },
        });
        defer parallel_parser.deinit();

        const start_time = std.time.nanoTimestamp();
        var tokens = try parallel_parser.parse(json_data);
        defer tokens.deinit();
        const time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));

        const throughput_mbps = calculateThroughput(json_data.len, time);
        std.debug.print("  Throughput: {d:.2} MB/s\n", .{throughput_mbps});
        std.debug.print("  Chunks: {}\n", .{parallel_parser.getStats().num_chunks});
    }

    std.debug.print("\n========================================\n", .{});
}

fn generateLargeJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("{\n");
    try buffer.appendSlice("  \"data\": [\n");

    var current_size: usize = buffer.items.len;
    var item_count: usize = 0;

    while (current_size < target_size) {
        if (item_count > 0) {
            try buffer.appendSlice(",\n");
        }

        try buffer.writer().print(
            \\    {{
            \\      "id": {},
            \\      "name": "Item {}",
            \\      "description": "This is a longer description for item {} to add more data",
            \\      "values": [1.23, 4.56, 7.89, 10.11, 12.13],
            \\      "metadata": {{
            \\        "created": "2024-01-01T00:00:00Z",
            \\        "modified": "2024-01-02T00:00:00Z",
            \\        "tags": ["tag1", "tag2", "tag3"],
            \\        "active": true
            \\      }}
            \\    }}
        , .{ item_count, item_count, item_count });

        item_count += 1;
        current_size = buffer.items.len;
    }

    try buffer.appendSlice("\n  ]\n}\n");

    return allocator.dupe(u8, buffer.items);
}

fn calculateThroughput(bytes: usize, nanoseconds: u64) f64 {
    const seconds = @as(f64, @floatFromInt(nanoseconds)) / 1_000_000_000.0;
    const megabytes = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
    return megabytes / seconds;
}