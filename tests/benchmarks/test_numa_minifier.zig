// Test NUMA-aware minifier
const std = @import("std");
const TurboMinifierNuma = @import("src/modes/turbo_minifier_numa.zig").TurboMinifierNuma;
const TurboMinifierParallelSimple = @import("src/modes/turbo_minifier_parallel_simple.zig").TurboMinifierParallelSimple;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n🔧 NUMA-Aware Minifier Test\n", .{});
    try stdout.print("===========================\n\n", .{});

    // Initialize NUMA minifier
    var numa_minifier = try TurboMinifierNuma.init(allocator, .{});
    defer numa_minifier.deinit();

    const stats = numa_minifier.getStats();
    try stdout.print("System Info:\n", .{});
    try stdout.print("  NUMA Available: {}\n", .{stats.numa_available});
    try stdout.print("  NUMA Nodes: {d}\n", .{stats.node_count});
    try stdout.print("  Thread Count: {d}\n", .{stats.thread_count});
    try stdout.print("  Threads per Node: {d}\n\n", .{stats.threads_per_node});

    // Test different sizes
    const test_sizes = [_]struct { size: usize, name: []const u8 }{
        .{ .size = 10 * 1024 * 1024, .name = "10 MB" },
        .{ .size = 50 * 1024 * 1024, .name = "50 MB" },
        .{ .size = 100 * 1024 * 1024, .name = "100 MB" },
    };

    for (test_sizes) |test_case| {
        try stdout.print("Testing {s} file:\n", .{test_case.name});

        const input = try generateTestJson(allocator, test_case.size);
        defer allocator.free(input);

        const output_numa = try allocator.alloc(u8, input.len);
        defer allocator.free(output_numa);
        const output_simple = try allocator.alloc(u8, input.len);
        defer allocator.free(output_simple);

        // Test NUMA-aware implementation
        const numa_start = std.time.nanoTimestamp();
        const numa_len = try numa_minifier.minify(input, output_numa);
        const numa_end = std.time.nanoTimestamp();
        const numa_ns = @as(u64, @intCast(numa_end - numa_start));
        const numa_ms = numa_ns / 1_000_000;
        const numa_throughput = if (numa_ms > 0)
            (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(numa_ms)) * 1000.0 / (1024.0 * 1024.0))
        else
            0.0;

        // Test simple parallel for comparison
        var simple_parallel = try TurboMinifierParallelSimple.init(allocator, .{});
        defer simple_parallel.deinit();

        const simple_start = std.time.nanoTimestamp();
        const simple_len = try simple_parallel.minify(input, output_simple);
        const simple_end = std.time.nanoTimestamp();
        const simple_ns = @as(u64, @intCast(simple_end - simple_start));
        const simple_ms = simple_ns / 1_000_000;
        const simple_throughput = if (simple_ms > 0)
            (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(simple_ms)) * 1000.0 / (1024.0 * 1024.0))
        else
            0.0;

        const match = (numa_len == simple_len);
        const improvement = if (simple_ms > 0 and numa_ms > 0)
            ((@as(f64, @floatFromInt(simple_ms)) - @as(f64, @floatFromInt(numa_ms))) / @as(f64, @floatFromInt(simple_ms)) * 100.0)
        else
            0.0;

        try stdout.print("  NUMA-aware:     {d:>5} ms ({d:>7.1} MB/s)\n", .{ numa_ms, numa_throughput });
        try stdout.print("  Simple parallel: {d:>5} ms ({d:>7.1} MB/s)\n", .{ simple_ms, simple_throughput });
        try stdout.print("  Improvement:     {d:>5.1}% {s}\n\n", .{ improvement, if (match) "✅" else "❌" });
    }
}

fn generateTestJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("{\n");

    var key_counter: usize = 0;
    while (buffer.items.len < target_size - 100) {
        if (key_counter > 0) {
            try buffer.appendSlice(",\n");
        }

        const pattern = key_counter % 4;
        switch (pattern) {
            0 => try buffer.writer().print("  \"key_{d}\"  :  \"value with    spaces    and more\"", .{key_counter}),
            1 => try buffer.writer().print("  \"data_{d}\" : {{   \"num\" :   {d},   \"str\" : \"test\"   }}", .{ key_counter, key_counter * 42 }),
            2 => try buffer.writer().print("  \"array_{d}\" : [  1,   2,    3,     4,      5  ]", .{key_counter}),
            3 => try buffer.writer().print("  \"nested_{d}\" : {{  \"a\" : {{  \"b\" :  \"c\"  }}  }}", .{key_counter}),
            else => unreachable,
        }

        key_counter += 1;
    }

    try buffer.appendSlice("\n}");
    return buffer.toOwnedSlice();
}
