// Debug test to see where TURBO V2 is hanging
const std = @import("std");
const TurboMinifierParallelV2 = @import("turbo_minifier_parallel_v2").TurboMinifierParallelV2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("TURBO V2 Debug Test\n", .{});
    try stdout.print("===================\n\n", .{});

    // Small test - should use single-threaded path
    {
        const input = "{\"test\":123}";
        const output = try allocator.alloc(u8, input.len);
        defer allocator.free(output);

        const config = TurboMinifierParallelV2.ParallelConfig{
            .thread_count = 2,
            .enable_work_stealing = false,
            .enable_numa = false,
            .adaptive_chunking = false,
        };

        try stdout.print("Test 1: Small input (single-threaded path)...\n", .{});
        var minifier = try TurboMinifierParallelV2.init(allocator, config);
        defer minifier.deinit();

        const result_len = try minifier.minify(input, output);
        try stdout.print("Success! Output: {s}\n\n", .{output[0..result_len]});
    }

    // Larger test - should trigger parallel path
    {
        // Generate 256KB of JSON (above default chunk_size)
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        try buffer.appendSlice("{\n");
        for (0..1000) |i| {
            if (i > 0) try buffer.appendSlice(",\n");
            try buffer.writer().print("  \"key_{d}\": \"value_{d}\"", .{ i, i });
        }
        try buffer.appendSlice("\n}");

        const input = try buffer.toOwnedSlice();
        defer allocator.free(input);

        const output = try allocator.alloc(u8, input.len);
        defer allocator.free(output);

        const config = TurboMinifierParallelV2.ParallelConfig{
            .thread_count = 2,
            .enable_work_stealing = false,
            .enable_numa = false,
            .adaptive_chunking = false,
        };

        try stdout.print("Test 2: Large input ({d} KB, parallel path)...\n", .{input.len / 1024});
        try stdout.print("Creating minifier...\n", .{});

        var minifier = try TurboMinifierParallelV2.init(allocator, config);
        defer minifier.deinit();

        try stdout.print("Starting minification...\n", .{});
        const start = std.time.milliTimestamp();

        const result_len = try minifier.minify(input, output);

        const end = std.time.milliTimestamp();
        try stdout.print("Success! Processed {d} bytes in {d}ms\n", .{ result_len, end - start });
        try stdout.print("Throughput: {d:.2} MB/s\n", .{@as(f64, @floatFromInt(input.len)) / @as(f64, @floatFromInt(end - start)) / 1024.0});
    }
}
