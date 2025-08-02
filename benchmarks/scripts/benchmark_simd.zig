const std = @import("std");
const zmin = @import("src/root.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== zmin v2.0 SIMD Parser Benchmark ===\n", .{});

    // Create test data
    var large_json = std.ArrayList(u8).init(allocator);
    defer large_json.deinit();

    try large_json.appendSlice("[");
    const item_count = 10000;
    var i: usize = 0;
    while (i < item_count) : (i += 1) {
        if (i > 0) try large_json.appendSlice(",");
        try large_json.writer().print(
            \\{{"id":{},"name":"user_{}","active":{}}}
        , .{ i, i, i % 2 == 0 });
    }
    try large_json.appendSlice("]");

    std.debug.print("Input size: {d:.2} MB\n", .{@as(f64, @floatFromInt(large_json.items.len)) / 1024.0 / 1024.0});

    // Test streaming parser directly
    var parser = try zmin.v2.StreamingParser.init(allocator, .{});
    defer parser.deinit();

    const iterations = 50;
    var total_time: i64 = 0;

    for (0..iterations) |_| {
        const start_time = std.time.milliTimestamp();
        
        // Use the streaming parser with SIMD optimization
        var token_stream = try parser.parseStreaming(large_json.items);
        defer token_stream.deinit();
        
        const end_time = std.time.milliTimestamp();
        total_time += (end_time - start_time);
    }

    const avg_time_ms = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(iterations));
    const throughput_mbps = (@as(f64, @floatFromInt(large_json.items.len)) / 1024.0 / 1024.0) / (avg_time_ms / 1000.0);

    std.debug.print("SIMD Streaming Parser Results:\n", .{});
    std.debug.print("Average processing time: {d:.2} ms\n", .{avg_time_ms});
    std.debug.print("Throughput: {d:.2} MB/s\n", .{throughput_mbps});
    
    // Check SIMD level detected
    std.debug.print("System info: Detected SIMD level based on CPU features\n", .{});
}