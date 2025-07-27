const std = @import("std");
const src = @import("src");
const ParallelMinifier = src.parallel.ParallelMinifier;
const Config = src.parallel.Config;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read the large test file
    const file_content = std.fs.cwd().readFileAlloc(allocator, "/tmp/very_large_test.json", 10 * 1024 * 1024) catch |err| {
        std.debug.print("Error reading file: {}\n", .{err});
        return;
    };
    defer allocator.free(file_content);

    std.debug.print("Testing with {} bytes of JSON data\n", .{file_content.len});

    // Test single-threaded performance
    {
        var output_buffer = std.ArrayList(u8).init(allocator);
        defer output_buffer.deinit();

        const start_time = std.time.nanoTimestamp();

        var minifier = try ParallelMinifier.create(allocator, output_buffer.writer().any(), ParallelMinifier.Config{
            .buffer_size = 256 * 1024,
            .enable_pipeline = false,
        });
        defer minifier.destroy();

        try minifier.process(file_content);
        try minifier.flush();

        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

        std.debug.print("Single-threaded: {d:.2} ms\n", .{duration_ms});
    }

    // Test multi-threaded performance
    {
        var output_buffer = std.ArrayList(u8).init(allocator);
        defer output_buffer.deinit();

        const start_time = std.time.nanoTimestamp();

        var minifier = try ParallelMinifier.create(allocator, output_buffer.writer().any(), ParallelMinifier.Config{
            .thread_count = 4,
            .chunk_size = 64 * 1024,
        });
        defer minifier.destroy();

        try minifier.process(file_content);
        try minifier.flush();

        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

        std.debug.print("Multi-threaded (4 threads): {d:.2} ms\n", .{duration_ms});
    }
}
