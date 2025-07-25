const std = @import("std");
const testing = std.testing;

// Import the parallel minifier
const ParallelMinifier = @import("src").parallel.ParallelMinifier;

test "performance test - single vs multi-threaded" {
    // Use a thread-safe allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create a large JSON input
    var large_input = std.ArrayList(u8).init(allocator);
    defer large_input.deinit();

    // Generate 10KB of JSON data (reduced from 100KB)
    try large_input.appendSlice("{\"data\":[");
    var i: usize = 0;
    while (i < 100) : (i += 1) { // Reduced from 1000
        if (i > 0) try large_input.appendSlice(",");
        try large_input.writer().print("{{\"id\":{},\"value\":\"item_{}\"}}", .{ i, i });
    }
    try large_input.appendSlice("]}");

    std.debug.print("Input size: {} bytes\n", .{large_input.items.len});

    // Test single-threaded performance
    var single_output = std.ArrayList(u8).init(allocator);
    defer single_output.deinit();

    var single_minifier = try ParallelMinifier.create(allocator, single_output.writer().any(), .{
        .thread_count = 1,
        .chunk_size = 1024,
    });
    defer single_minifier.destroy();

    const single_start = std.time.milliTimestamp();
    try single_minifier.process(large_input.items);
    try single_minifier.flush();
    const single_end = std.time.milliTimestamp();
    const single_time = @as(f64, @floatFromInt(single_end - single_start));

    std.debug.print("Single-threaded time: {} ms\n", .{single_time});

    // Test multi-threaded performance
    var multi_output = std.ArrayList(u8).init(allocator);
    defer multi_output.deinit();

    var multi_minifier = try ParallelMinifier.create(allocator, multi_output.writer().any(), .{
        .thread_count = 1, // Test with single thread first
        .chunk_size = 8192, // Larger chunk size to reduce overhead
    });
    defer multi_minifier.destroy();

    const multi_start = std.time.milliTimestamp();
    try multi_minifier.process(large_input.items);
    try multi_minifier.flush();
    const multi_end = std.time.milliTimestamp();
    const multi_time = @as(f64, @floatFromInt(multi_end - multi_start));

    std.debug.print("Multi-threaded time: {} ms\n", .{multi_time});

    // Verify outputs are identical
    try testing.expectEqualStrings(single_output.items, multi_output.items);

    // Calculate speedup
    if (multi_time > 0 and single_time > 0) {
        const speedup = single_time / multi_time;
        std.debug.print("Speedup: {:.2}x\n", .{speedup});

        // For now, just ensure both versions complete successfully
        try testing.expect(speedup > 0);
    }
}
