const std = @import("std");
const testing = std.testing;

// Import the modules we want to test for memory leaks
const MinifyingParser = @import("src").minifier.MinifyingParser;
const ParallelMinifier = @import("src").parallel.ParallelMinifier;

test "memory - minifier no leaks" {
    // Use GeneralPurposeAllocator to detect memory leaks
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const input = "{\"test\":\"value\",\"number\":42}";
    const expected = "{\"test\":\"value\",\"number\":42}";

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(allocator, output.writer().any());
    defer parser.deinit(allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "memory - parallel minifier no leaks" {
    // Use GeneralPurposeAllocator to detect memory leaks
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const input = "{\"test\":\"value\",\"number\":42}";
    const expected = "{\"test\":\"value\",\"number\":42}";

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    var minifier = try ParallelMinifier.create(allocator, output.writer().any(), .{
        .thread_count = 1,
        .chunk_size = 1024,
    });
    defer minifier.destroy();

    try minifier.process(input);
    try minifier.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "memory - large input stress test" {
    // Use GeneralPurposeAllocator to detect memory leaks
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a large JSON input to stress test memory management
    var large_input = std.ArrayList(u8).init(allocator);
    defer large_input.deinit();

    try large_input.appendSlice("{\"data\":[");
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        if (i > 0) try large_input.appendSlice(",");
        try large_input.writer().print("{{\"id\":{},\"value\":\"item_{}\"}}", .{ i, i });
    }
    try large_input.appendSlice("]}");

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(allocator, output.writer().any());
    defer parser.deinit(allocator);

    try parser.feed(large_input.items);
    try parser.flush();

    // Verify output is valid and not empty
    try testing.expect(output.items.len > 0);
    try testing.expect(output.items[0] == '{');
    try testing.expect(output.items[output.items.len - 1] == '}');
}

test "memory - multiple allocations and deallocations" {
    // Use GeneralPurposeAllocator to detect memory leaks
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const input = "{\"test\":\"value\"}";

    // Test multiple minifier instances to ensure proper cleanup
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(allocator, output.writer().any());
        defer parser.deinit(allocator);

        try parser.feed(input);
        try parser.flush();

        try testing.expectEqualStrings(input, output.items);
    }
}