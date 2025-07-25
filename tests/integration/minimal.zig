const std = @import("std");
const testing = std.testing;

// Import the minifier directly
const MinifyingParser = @import("src").minifier.MinifyingParser;

test "integration - minimal functionality" {
    const input = "{\"test\":\"value\"}";
    const expected = "{\"test\":\"value\"}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}
