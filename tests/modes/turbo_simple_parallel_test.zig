// Test for TURBO Simple Parallel implementation
const std = @import("std");
const TurboMinifierParallelSimple = @import("turbo_minifier_parallel_simple").TurboMinifierParallelSimple;
const TurboMinifierSimple = @import("turbo_minifier_simple").TurboMinifierSimple;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\nTURBO Simple Parallel Implementation Test\n", .{});
    try stdout.print("=========================================\n\n", .{});

    // Test different sizes
    const test_sizes = [_]usize{
        100 * 1024, // 100KB
        1024 * 1024, // 1MB
        10 * 1024 * 1024, // 10MB
    };

    for (test_sizes) |size| {
        try stdout.print("Testing {d} KB file:\n", .{size / 1024});

        const input = try generateTestJson(allocator, size);
        defer allocator.free(input);

        const output1 = try allocator.alloc(u8, input.len);
        defer allocator.free(output1);
        const output2 = try allocator.alloc(u8, input.len);
        defer allocator.free(output2);

        // Test simple implementation
        var simple = TurboMinifierSimple.init(allocator);
        const simple_start = std.time.milliTimestamp();
        const simple_len = try simple.minify(input, output1);
        const simple_end = std.time.milliTimestamp();
        const simple_time = simple_end - simple_start;

        // Test parallel simple
        const thread_count = try std.Thread.getCpuCount();
        const config = TurboMinifierParallelSimple.Config{
            .thread_count = thread_count,
        };

        var parallel = try TurboMinifierParallelSimple.init(allocator, config);
        defer parallel.deinit();

        const parallel_start = std.time.milliTimestamp();
        const parallel_len = try parallel.minify(input, output2);
        const parallel_end = std.time.milliTimestamp();
        const parallel_time = parallel_end - parallel_start;

        // Verify results match
        const match = (simple_len == parallel_len) and
            std.mem.eql(u8, output1[0..simple_len], output2[0..parallel_len]);

        try stdout.print("  Simple:   {d} ms ({d:.2} MB/s)\n", .{ simple_time, if (simple_time > 0) @as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(simple_time)) / 1024.0 else 0.0 });
        try stdout.print("  Parallel: {d} ms ({d:.2} MB/s) with {d} threads\n", .{
            parallel_time,
            if (parallel_time > 0) @as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(parallel_time)) / 1024.0 else 0.0,
            thread_count,
        });
        try stdout.print("  Speedup:  {d:.2}x\n", .{if (parallel_time > 0) @as(f64, @floatFromInt(simple_time)) / @as(f64, @floatFromInt(parallel_time)) else 0.0});
        try stdout.print("  Match:    {s}\n\n", .{if (match) "✅" else "❌"});
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

        // Varied content
        const pattern = key_counter % 3;
        switch (pattern) {
            0 => try buffer.writer().print("  \"key_{d}\"  :  \"value with    spaces\"", .{key_counter}),
            1 => try buffer.writer().print("  \"data_{d}\" : {{ \"num\" : {d} }}", .{ key_counter, key_counter * 42 }),
            2 => try buffer.writer().print("  \"arr_{d}\" : [  1,   2,    3  ]", .{key_counter}),
            else => unreachable,
        }

        key_counter += 1;
    }

    try buffer.appendSlice("\n}");
    return buffer.toOwnedSlice();
}
