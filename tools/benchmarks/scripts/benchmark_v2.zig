const std = @import("std");
const zmin = @import("src/root.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== zmin v2.0 Performance Baseline Measurement ===\n", .{});

    // Create larger test data
    var large_json = std.ArrayList(u8).init(allocator);
    defer large_json.deinit();

    try large_json.appendSlice("[");
    const item_count = 10000; // 10k items for better measurement
    var i: usize = 0;
    while (i < item_count) : (i += 1) {
        if (i > 0) try large_json.appendSlice(",");
        try large_json.writer().print(
            \\{{"id":{},"name":"user_{}","email":"user{}@example.com","active":{},"data":{{"timestamp":{},"value":{}}}}}
        , .{ i, i, i, i % 2 == 0, std.time.timestamp(), @as(i64, @intCast(i)) });
    }
    try large_json.appendSlice("]");

    std.debug.print("Input size: {d:.2} MB\n", .{@as(f64, @floatFromInt(large_json.items.len)) / 1024.0 / 1024.0});

    // Benchmark v2 minification
    const iterations = 10;
    var total_time: i64 = 0;

    for (0..iterations) |_| {
        const start_time = std.time.milliTimestamp();
        const output = try zmin.minifyV2(allocator, large_json.items);
        const end_time = std.time.milliTimestamp();
        allocator.free(output);
        
        total_time += (end_time - start_time);
    }

    const avg_time_ms = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(iterations));
    const throughput_mbps = (@as(f64, @floatFromInt(large_json.items.len)) / 1024.0 / 1024.0) / (avg_time_ms / 1000.0);

    std.debug.print("Average processing time: {d:.2} ms\n", .{avg_time_ms});
    std.debug.print("Throughput: {d:.2} MB/s\n", .{throughput_mbps});
    std.debug.print("Baseline established for SIMD optimization phase!\n", .{});
}