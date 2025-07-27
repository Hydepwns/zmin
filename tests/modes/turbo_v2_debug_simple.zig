// Simple debug test for TURBO V2 parallel implementation
const std = @import("std");
const TurboMinifierParallelV2 = @import("turbo_minifier_parallel_v2").TurboMinifierParallelV2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("TURBO V2 Parallel Debug\n", .{});
    try stdout.print("=======================\n\n", .{});

    // Test with a 1MB file (just above chunk threshold)
    const input_size = 512 * 1024; // 512KB - twice the chunk size
    const input = try generateSimpleJson(allocator, input_size);
    defer allocator.free(input);

    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);

    try stdout.print("Input size: {d} KB\n", .{input.len / 1024});

    const config = TurboMinifierParallelV2.ParallelConfig{
        .thread_count = 2, // Just 2 threads to simplify
        .enable_work_stealing = false,
        .enable_numa = false,
        .adaptive_chunking = false,
        .chunk_size = 256 * 1024, // 256KB chunks
    };

    try stdout.print("Creating minifier with 2 threads...\n", .{});
    var minifier = try TurboMinifierParallelV2.init(allocator, config);
    defer minifier.deinit();

    try stdout.print("Minifier created successfully\n", .{});
    try stdout.print("Starting parallel minification...\n", .{});

    const start = std.time.milliTimestamp();
    const result_len = try minifier.minify(input, output);
    const end = std.time.milliTimestamp();

    try stdout.print("Minification completed!\n", .{});
    try stdout.print("  Input: {d} bytes\n", .{input.len});
    try stdout.print("  Output: {d} bytes\n", .{result_len});
    try stdout.print("  Time: {d} ms\n", .{end - start});
    try stdout.print("  Compression: {d:.1}%\n", .{@as(f64, @floatFromInt(result_len)) / @as(f64, @floatFromInt(input.len)) * 100.0});

    // Verify output starts and ends correctly
    if (result_len > 10) {
        try stdout.print("  Output preview: {s}...{s}\n", .{
            output[0..@min(20, result_len)],
            output[@max(0, result_len - 20)..result_len],
        });
    }
}

fn generateSimpleJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("{\n");

    var key_counter: usize = 0;
    while (buffer.items.len < target_size - 100) {
        if (key_counter > 0) {
            try buffer.appendSlice(",\n");
        }

        try buffer.writer().print("  \"key_{d}\"  :  \"value_{d}\"", .{ key_counter, key_counter });
        key_counter += 1;
    }

    try buffer.appendSlice("\n}");

    return buffer.toOwnedSlice();
}
