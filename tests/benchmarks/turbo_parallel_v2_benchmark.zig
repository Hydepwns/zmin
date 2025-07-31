// Benchmark for TURBO Parallel V2 Implementation
// Tests throughput, scalability, and efficiency improvements

const std = @import("std");
const TurboMinifierParallelV2 = @import("turbo_minifier_parallel_v2").TurboMinifierParallelV2;
const TurboMinifierSimple = @import("turbo_minifier_simple").TurboMinifierSimple;

const BENCHMARK_ITERATIONS = 3;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("TURBO Mode Parallel V2 Benchmark\n", .{});
    try stdout.print("================================\n\n", .{});

    // Test various file sizes
    const test_sizes = [_]struct { name: []const u8, size: usize }{
        .{ .name = "Small (100KB)", .size = 100 * 1024 },
        .{ .name = "Medium (1MB)", .size = 1024 * 1024 },
        .{ .name = "Large (10MB)", .size = 10 * 1024 * 1024 },
    };

    // Test with different thread counts
    const thread_counts = [_]usize{ 1, 2, 4, 8, 16 };

    for (test_sizes) |test_case| {
        try stdout.print("Testing {s}:\n", .{test_case.name});
        try stdout.print("-" ** 80 ++ "\n", .{});

        // Generate test data
        const input = try generateTestJson(allocator, test_case.size);
        defer allocator.free(input);

        const output = try allocator.alloc(u8, input.len);
        defer allocator.free(output);

        // Benchmark simple implementation (baseline)
        var simple_minifier = TurboMinifierSimple.init(allocator);
        const baseline_time = try benchmarkSimple(&simple_minifier, input, output);
        const baseline_throughput = calculateThroughput(input.len, baseline_time);

        try stdout.print("  Baseline (Simple): {d:.2} MB/s\n", .{baseline_throughput});

        // Benchmark parallel implementation with different thread counts
        for (thread_counts) |thread_count| {
            const config = TurboMinifierParallelV2.ParallelConfig{
                .thread_count = thread_count,
                .enable_work_stealing = true,
                .enable_numa = true,
                .adaptive_chunking = true,
            };

            var parallel_minifier = try TurboMinifierParallelV2.init(allocator, config);
            defer parallel_minifier.deinit();

            const parallel_time = try benchmarkParallel(&parallel_minifier, input, output);
            const parallel_throughput = calculateThroughput(input.len, parallel_time);
            const speedup = parallel_throughput / baseline_throughput;
            const efficiency = speedup / @as(f64, @floatFromInt(thread_count)) * 100.0;

            // Get detailed stats
            const stats = parallel_minifier.getPerformanceStats();

            try stdout.print("  {d:2} threads: {d:6.2} MB/s (speedup: {d:.2}x, efficiency: {d:.1}%, steal ratio: {d:.2})\n", .{
                thread_count,
                parallel_throughput,
                speedup,
                efficiency,
                stats.work_steal_ratio,
            });
        }

        try stdout.print("\n", .{});
    }

    // Test work-stealing effectiveness
    try stdout.print("Work-Stealing Analysis:\n", .{});
    try stdout.print("-" ** 80 ++ "\n", .{});
    try testWorkStealingEffectiveness(allocator);

    // Test adaptive chunking
    try stdout.print("\nAdaptive Chunking Analysis:\n", .{});
    try stdout.print("-" ** 80 ++ "\n", .{});
    try testAdaptiveChunking(allocator);
}

fn benchmarkSimple(minifier: *TurboMinifierSimple, input: []const u8, output: []u8) !u64 {
    var total_time: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        const start = std.time.nanoTimestamp();
        _ = try minifier.minify(input, output);
        const end = std.time.nanoTimestamp();
        total_time += @intCast(end - start);
    }

    return total_time / BENCHMARK_ITERATIONS;
}

fn benchmarkParallel(minifier: *TurboMinifierParallelV2, input: []const u8, output: []u8) !u64 {
    var total_time: u64 = 0;

    // Warm up
    _ = try minifier.minify(input, output);

    for (0..BENCHMARK_ITERATIONS) |_| {
        const start = std.time.nanoTimestamp();
        _ = try minifier.minify(input, output);
        const end = std.time.nanoTimestamp();
        total_time += @intCast(end - start);
    }

    return total_time / BENCHMARK_ITERATIONS;
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

        // Add some variety in the JSON structure
        const pattern = key_counter % 4;
        switch (pattern) {
            0 => {
                // Simple string value with whitespace
                try buffer.writer().print("  \"key_{d}\"  :  \"value with    spaces    and\\ttabs\"", .{key_counter});
            },
            1 => {
                // Nested object
                try buffer.writer().print("  \"nested_{d}\" : {{ \"inner\" : \"value\", \"number\" : {d} }}", .{ key_counter, key_counter * 42 });
            },
            2 => {
                // Array with whitespace
                try buffer.writer().print("  \"array_{d}\" : [  1,   2,    3,     4,      5  ]", .{key_counter});
            },
            3 => {
                // Long string to test bulk copying
                try buffer.appendSlice("  \"long_string\" : \"");
                for (0..100) |_| {
                    try buffer.appendSlice("Lorem ipsum dolor sit amet ");
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

fn testWorkStealingEffectiveness(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    // Create unbalanced workload
    const chunk_sizes = [_]usize{
        10 * 1024, // 10KB
        100 * 1024, // 100KB
        1024 * 1024, // 1MB
        5 * 1024 * 1024, // 5MB
    };

    var total_size: usize = 0;
    for (chunk_sizes) |size| {
        total_size += size;
    }

    const input = try generateTestJson(allocator, total_size);
    defer allocator.free(input);

    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);

    // Test with and without work stealing
    const configs = [_]struct { name: []const u8, config: TurboMinifierParallelV2.ParallelConfig }{
        .{ .name = "Without work-stealing", .config = .{ .thread_count = 4, .enable_work_stealing = false } },
        .{ .name = "With work-stealing", .config = .{ .thread_count = 4, .enable_work_stealing = true } },
    };

    for (configs) |test_config| {
        var minifier = try TurboMinifierParallelV2.init(allocator, test_config.config);
        defer minifier.deinit();

        const time = try benchmarkParallel(&minifier, input, output);
        const throughput = calculateThroughput(input.len, time);
        const stats = minifier.getPerformanceStats();

        try stdout.print("  {s}: {d:.2} MB/s (local hit rate: {d:.2}, steal ratio: {d:.2})\n", .{
            test_config.name,
            throughput,
            stats.local_hit_rate,
            stats.work_steal_ratio,
        });
    }
}

fn testAdaptiveChunking(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    // Generate JSON with varying complexity
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("{\n");

    // Add deeply nested structure
    try buffer.appendSlice("  \"deeply_nested\": ");
    for (0..10) |_| {
        try buffer.appendSlice("{\"level\":");
    }
    try buffer.appendSlice("\"bottom\"");
    for (0..10) |_| {
        try buffer.appendSlice("}");
    }
    try buffer.appendSlice(",\n");

    // Add large array
    try buffer.appendSlice("  \"large_array\": [");
    for (0..1000) |i| {
        if (i > 0) try buffer.appendSlice(",");
        try buffer.writer().print("{d}", .{i});
    }
    try buffer.appendSlice("],\n");

    // Add many small objects
    for (0..100) |i| {
        try buffer.writer().print("  \"obj_{d}\": {{\"id\": {d}, \"data\": \"value\"}},\n", .{ i, i });
    }

    try buffer.appendSlice("  \"final\": true\n}");

    const input = try buffer.toOwnedSlice();
    defer allocator.free(input);

    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);

    // Test with different chunking strategies
    const configs = [_]struct {
        name: []const u8,
        config: TurboMinifierParallelV2.ParallelConfig,
    }{
        .{
            .name = "Fixed chunking",
            .config = .{ .thread_count = 4, .adaptive_chunking = false },
        },
        .{
            .name = "Adaptive chunking",
            .config = .{ .thread_count = 4, .adaptive_chunking = true },
        },
    };

    for (configs) |test_config| {
        var minifier = try TurboMinifierParallelV2.init(allocator, test_config.config);
        defer minifier.deinit();

        const time = try benchmarkParallel(&minifier, input, output);
        const throughput = calculateThroughput(input.len, time);
        const stats = minifier.getPerformanceStats();

        try stdout.print("  {s}: {d:.2} MB/s (chunks: {d}, efficiency: {d:.1}%)\n", .{
            test_config.name,
            throughput,
            stats.total_chunks,
            stats.thread_efficiency * 100.0,
        });
    }
}
