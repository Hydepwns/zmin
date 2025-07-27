// Performance test for TURBO V2 - single run to avoid timeouts
const std = @import("std");
const TurboMinifierParallelV2 = @import("turbo_minifier_parallel_v2").TurboMinifierParallelV2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("TURBO V2 Performance Test\n", .{});
    try stdout.print("=========================\n\n", .{});

    // Test sizes
    const sizes = [_]struct { name: []const u8, size: usize }{
        .{ .name = "1MB", .size = 1024 * 1024 },
        .{ .name = "5MB", .size = 5 * 1024 * 1024 },
        .{ .name = "10MB", .size = 10 * 1024 * 1024 },
    };

    const thread_count = try std.Thread.getCpuCount();
    try stdout.print("CPU threads: {d}\n\n", .{thread_count});

    for (sizes) |test_case| {
        try stdout.print("Testing {s}:\n", .{test_case.name});
        try stdout.print("-" ** 60 ++ "\n", .{});

        // Generate test data
        const input = try generateTestJson(allocator, test_case.size);
        defer allocator.free(input);

        const output = try allocator.alloc(u8, input.len);
        defer allocator.free(output);

        // Test with optimal config
        const config = TurboMinifierParallelV2.ParallelConfig{
            .thread_count = thread_count,
            .enable_work_stealing = true,
            .enable_numa = true,
            .adaptive_chunking = true,
        };

        var minifier = try TurboMinifierParallelV2.init(allocator, config);
        defer minifier.deinit();

        // Single run benchmark
        const start = std.time.nanoTimestamp();
        const output_len = try minifier.minify(input, output);
        const end = std.time.nanoTimestamp();

        const time_ns = @as(u64, @intCast(end - start));
        const throughput = calculateThroughput(input.len, time_ns);
        const compression_ratio = @as(f64, @floatFromInt(output_len)) / @as(f64, @floatFromInt(input.len)) * 100.0;

        try stdout.print("  Input size: {d} bytes\n", .{input.len});
        try stdout.print("  Output size: {d} bytes\n", .{output_len});
        try stdout.print("  Compression: {d:.1}%\n", .{compression_ratio});
        try stdout.print("  Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(time_ns)) / 1_000_000.0});
        try stdout.print("  Throughput: {d:.2} MB/s\n", .{throughput});

        // Get performance stats
        const stats = minifier.getPerformanceStats();
        try stdout.print("  Work steal ratio: {d:.2}\n", .{stats.work_steal_ratio});
        try stdout.print("  Thread efficiency: {d:.1}%\n", .{stats.thread_efficiency * 100.0});
        try stdout.print("\n", .{});
    }

    // Final verdict
    try stdout.print("Performance Summary:\n", .{});
    try stdout.print("===================\n", .{});
    try stdout.print("Target: 1.2-1.5 GB/s\n", .{});
    try stdout.print("Note: Single-run results may vary. Production benchmarks should use multiple iterations.\n", .{});
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

        // Mix of different JSON structures
        const pattern = key_counter % 4;
        switch (pattern) {
            0 => {
                try buffer.writer().print("  \"key_{d}\"  :  \"value with    spaces\"", .{key_counter});
            },
            1 => {
                try buffer.writer().print("  \"nested_{d}\" : {{ \"data\" : {d} }}", .{ key_counter, key_counter * 42 });
            },
            2 => {
                try buffer.writer().print("  \"array_{d}\" : [  1,   2,    3  ]", .{key_counter});
            },
            3 => {
                try buffer.appendSlice("  \"text\" : \"Lorem ipsum dolor sit amet\"");
            },
            else => unreachable,
        }

        current_size = buffer.items.len;
        key_counter += 1;
    }

    try buffer.appendSlice("\n}");

    return buffer.toOwnedSlice();
}
