// Quick benchmark to validate TURBO Parallel V2 performance claims
const std = @import("std");
const TurboMinifierParallelV2 = @import("turbo_minifier_parallel_v2").TurboMinifierParallelV2;
const TurboMinifierSimple = @import("turbo_minifier_simple").TurboMinifierSimple;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    try stdout.print("TURBO Parallel V2 Quick Validation\n", .{});
    try stdout.print("==================================\n\n", .{});
    
    // Test with 10MB file (good balance for parallel processing)
    const test_size = 10 * 1024 * 1024;
    const input = try generateTestJson(allocator, test_size);
    defer allocator.free(input);
    
    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);
    
    // Test simple baseline
    var simple_minifier = TurboMinifierSimple.init(allocator);
    const simple_start = std.time.nanoTimestamp();
    _ = try simple_minifier.minify(input, output);
    const simple_end = std.time.nanoTimestamp();
    const simple_time = @as(u64, @intCast(simple_end - simple_start));
    const simple_throughput = calculateThroughput(input.len, simple_time);
    
    try stdout.print("Baseline (Simple): {d:.2} MB/s\n\n", .{simple_throughput});
    
    // Test parallel V2 with optimal thread count
    const thread_count = try std.Thread.getCpuCount();
    const config = TurboMinifierParallelV2.ParallelConfig{
        .thread_count = thread_count,
        .enable_work_stealing = true,
        .enable_numa = true,
        .adaptive_chunking = true,
    };
    
    var parallel_minifier = try TurboMinifierParallelV2.init(allocator, config);
    defer parallel_minifier.deinit();
    
    // Warm up
    _ = try parallel_minifier.minify(input, output);
    
    // Actual benchmark
    const parallel_start = std.time.nanoTimestamp();
    _ = try parallel_minifier.minify(input, output);
    const parallel_end = std.time.nanoTimestamp();
    const parallel_time = @as(u64, @intCast(parallel_end - parallel_start));
    const parallel_throughput = calculateThroughput(input.len, parallel_time);
    
    const speedup = parallel_throughput / simple_throughput;
    const efficiency = speedup / @as(f64, @floatFromInt(thread_count)) * 100.0;
    const stats = parallel_minifier.getPerformanceStats();
    
    try stdout.print("Parallel V2 ({d} threads):\n", .{thread_count});
    try stdout.print("  Throughput: {d:.2} MB/s\n", .{parallel_throughput});
    try stdout.print("  Speedup: {d:.2}x\n", .{speedup});
    try stdout.print("  Efficiency: {d:.1}%\n", .{efficiency});
    try stdout.print("  Work Steal Ratio: {d:.2}\n", .{stats.work_steal_ratio});
    try stdout.print("  Thread Efficiency: {d:.1}%\n", .{stats.thread_efficiency * 100.0});
    try stdout.print("\n", .{});
    
    // Performance projection
    const projected_throughput = simple_throughput * @as(f64, @floatFromInt(thread_count)) * 0.5; // 50% efficiency
    try stdout.print("Projected Performance (50% efficiency): {d:.2} MB/s\n", .{projected_throughput});
    
    if (parallel_throughput >= 1200.0) {
        try stdout.print("\n✅ ACHIEVED 1.2+ GB/s target!\n", .{});
    } else if (parallel_throughput >= 1000.0) {
        try stdout.print("\n⚡ Close to target: {d:.2} MB/s (need 1200+ MB/s)\n", .{parallel_throughput});
    } else {
        try stdout.print("\n❌ Below target: {d:.2} MB/s (need 1200+ MB/s)\n", .{parallel_throughput});
    }
}

fn calculateThroughput(bytes: usize, time_ns: u64) f64 {
    const bytes_per_sec = (@as(f64, @floatFromInt(bytes)) * 1_000_000_000.0) / @as(f64, @floatFromInt(time_ns));
    return bytes_per_sec / (1024 * 1024); // MB/s
}

fn generateTestJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    try buffer.appendSlice("{\n");
    
    var current_size: usize = 2;
    var key_counter: usize = 0;
    
    while (current_size < target_size - 100) {
        if (key_counter > 0) {
            try buffer.appendSlice(",\n");
            current_size += 2;
        }
        
        // Generate varied JSON content
        const pattern = key_counter % 3;
        switch (pattern) {
            0 => {
                try buffer.writer().print("  \"key_{d}\"  :  \"value with    spaces    and\\ttabs\"", .{key_counter});
            },
            1 => {
                try buffer.writer().print("  \"nested_{d}\" : {{ \"inner\" : {d}, \"data\" : [1,  2,   3] }}", .{ key_counter, key_counter * 42 });
            },
            2 => {
                try buffer.appendSlice("  \"text\" : \"");
                for (0..50) |_| {
                    try buffer.appendSlice("Lorem ipsum ");
                }
                try buffer.appendSlice("\"");
            },
            else => unreachable,
        }
        
        current_size = buffer.items.len;
        key_counter += 1;
    }
    
    try buffer.appendSlice("\n}");
    
    return buffer.toOwnedSlice();
}