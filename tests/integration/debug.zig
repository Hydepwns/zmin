const std = @import("std");
const testing = std.testing;

// Import the simple parallel minifier
const ParallelMinifier = @import("src").parallel.simple.SimpleParallelMinifier;

test "debug - simple_parallel_minifier output" {
    const input = "{\"test\":\"value\"}";
    const expected = "{\"test\":\"value\"}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var minifier = try ParallelMinifier.init(testing.allocator, output.writer().any(), .{
        .thread_count = 1,
        .chunk_size = 1024,
    });
    defer minifier.deinit();

    try minifier.process(input);
    try minifier.flush();

    // SimpleParallelMinifier stores output internally, not in the provided writer
    // Use getOutput() to retrieve the processed result
    const actual_output = minifier.getOutput();
    try testing.expectEqualStrings(expected, actual_output);
}
