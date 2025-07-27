// Final benchmark for TURBO V2 - direct performance measurement
const std = @import("std");
const TurboMinifierParallelV2 = @import("turbo_minifier_parallel_v2").TurboMinifierParallelV2;
const TurboMinifierSimple = @import("turbo_minifier_simple").TurboMinifierSimple;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\nTURBO V2 Final Performance Validation\n", .{});
    try stdout.print("=====================================\n\n", .{});

    // Test with 50MB file (as per roadmap, this achieved 833 MB/s baseline)
    const test_size = 50 * 1024 * 1024;
    try stdout.print("Generating {d}MB test file...\n", .{test_size / 1024 / 1024});

    const input = try generateLargeJson(allocator, test_size);
    defer allocator.free(input);

    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);

    try stdout.print("Test file size: {d} bytes\n\n", .{input.len});

    // Baseline with simple implementation
    try stdout.print("Running baseline (TurboMinifierSimple)...\n", .{});
    var simple_minifier = TurboMinifierSimple.init(allocator);

    const simple_start = std.time.nanoTimestamp();
    const simple_len = try simple_minifier.minify(input, output);
    const simple_end = std.time.nanoTimestamp();

    const simple_time_ns = @as(u64, @intCast(simple_end - simple_start));
    const simple_throughput = calculateThroughput(input.len, simple_time_ns);

    try stdout.print("  Output size: {d} bytes\n", .{simple_len});
    try stdout.print("  Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(simple_time_ns)) / 1_000_000.0});
    try stdout.print("  Throughput: {d:.2} MB/s\n\n", .{simple_throughput});

    // Test with parallel V2
    const thread_count = try std.Thread.getCpuCount();
    try stdout.print("Running TURBO V2 with {d} threads...\n", .{thread_count});

    const config = TurboMinifierParallelV2.ParallelConfig{
        .thread_count = thread_count,
        .enable_work_stealing = true,
        .enable_numa = true,
        .adaptive_chunking = true,
        .chunk_size = 1024 * 1024, // 1MB chunks for better parallelism
    };

    var parallel_minifier = try TurboMinifierParallelV2.init(allocator, config);
    defer parallel_minifier.deinit();

    // Warm up
    _ = try parallel_minifier.minify(input[0..@min(1024 * 1024, input.len)], output);

    const parallel_start = std.time.nanoTimestamp();
    const parallel_len = try parallel_minifier.minify(input, output);
    const parallel_end = std.time.nanoTimestamp();

    const parallel_time_ns = @as(u64, @intCast(parallel_end - parallel_start));
    const parallel_throughput = calculateThroughput(input.len, parallel_time_ns);

    try stdout.print("  Output size: {d} bytes\n", .{parallel_len});
    try stdout.print("  Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(parallel_time_ns)) / 1_000_000.0});
    try stdout.print("  Throughput: {d:.2} MB/s\n", .{parallel_throughput});

    const speedup = parallel_throughput / simple_throughput;
    const efficiency = speedup / @as(f64, @floatFromInt(thread_count)) * 100.0;

    try stdout.print("\nPerformance Analysis:\n", .{});
    try stdout.print("  Speedup: {d:.2}x\n", .{speedup});
    try stdout.print("  Parallel efficiency: {d:.1}%\n", .{efficiency});

    const stats = parallel_minifier.getPerformanceStats();
    try stdout.print("  Work steal ratio: {d:.2}\n", .{stats.work_steal_ratio});
    try stdout.print("  Thread efficiency: {d:.1}%\n", .{stats.thread_efficiency * 100.0});

    try stdout.print("\nTarget Performance: 1.2-1.5 GB/s\n", .{});
    if (parallel_throughput >= 1200.0) {
        try stdout.print("✅ ACHIEVED: {d:.2} MB/s\n", .{parallel_throughput});
    } else if (parallel_throughput >= 1000.0) {
        try stdout.print("⚡ CLOSE: {d:.2} MB/s (need 1200+ MB/s)\n", .{parallel_throughput});
    } else {
        try stdout.print("❌ BELOW TARGET: {d:.2} MB/s (need 1200+ MB/s)\n", .{parallel_throughput});
    }
}

fn calculateThroughput(bytes: usize, time_ns: u64) f64 {
    const bytes_per_sec = (@as(f64, @floatFromInt(bytes)) * 1_000_000_000.0) / @as(f64, @floatFromInt(time_ns));
    return bytes_per_sec / (1024 * 1024); // MB/s
}

fn generateLargeJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("{\n");

    var key_counter: usize = 0;
    while (buffer.items.len < target_size - 1000) {
        if (key_counter > 0) {
            try buffer.appendSlice(",\n");
        }

        // Generate realistic JSON data
        try buffer.writer().print(
            \\  "record_{d}": {{
            \\    "id": {d},
            \\    "name": "Test User {d}",
            \\    "email": "user{d}@example.com",
            \\    "data": {{
            \\      "values": [1, 2, 3, 4, 5],
            \\      "status": "active",
            \\      "timestamp": 1234567890
            \\    }}
            \\  }}
        , .{ key_counter, key_counter, key_counter, key_counter });

        key_counter += 1;
    }

    try buffer.appendSlice("\n}");

    return buffer.toOwnedSlice();
}
