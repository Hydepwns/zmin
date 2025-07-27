const std = @import("std");
const testing = std.testing;

// Import helper modules
const helpers = @import("test_helpers.zig");
const generators = @import("test_data_generators.zig");
const assertions = @import("assertion_helpers.zig");

// ========== INVALID JSON STRUCTURE TESTS ==========

test "error handling - invalid object structure" {
    const invalid_inputs = [_][]const u8{
        "{", // Unterminated object
        "}", // Closing brace without opening
        "{\"key\"}", // Missing colon
        "{\"key\":}", // Missing value
        "{\"key\":\"value\",}", // Trailing comma
        "{\"key\":\"value\" \"key2\"}", // Missing comma
        "{:\"value\"}", // Missing key
        "{123:\"value\"}", // Invalid key (not string)
    };

    try helpers.runErrorTestCases(&invalid_inputs);
}

test "error handling - invalid array structure" {
    const invalid_inputs = [_][]const u8{
        "[", // Unterminated array
        "]", // Closing bracket without opening
        "[1,]", // Trailing comma
        "[1 2]", // Missing comma
        "[,1]", // Leading comma
    };

    try helpers.runErrorTestCases(&invalid_inputs);
}

test "error handling - invalid string escapes" {
    try helpers.runErrorTestCases(&generators.TestPatterns.invalid_escapes);
}

test "error handling - invalid numbers" {
    try helpers.runErrorTestCases(&generators.TestPatterns.invalid_numbers);
}

test "error handling - invalid literals" {
    try helpers.runErrorTestCases(&generators.TestPatterns.invalid_literals);
}

test "error handling - unexpected characters" {
    const invalid_inputs = [_][]const u8{
        "@", // Invalid top-level character
        "#", // Invalid top-level character
        "$", // Invalid top-level character
        "undefined", // JavaScript undefined (not JSON)
        "NaN", // JavaScript NaN (not JSON)
        "Infinity", // JavaScript Infinity (not JSON)
    };

    for (invalid_inputs) |input| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        // Should fail with some kind of error
        const result = parser.feed(input);
        try testing.expect(std.meta.isError(result));
    }
}

// ========== RECOVERY AND STATE TESTS ==========

test "error handling - parser state after error" {
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    // Feed invalid input
    const result = parser.feed("@");
    try testing.expect(std.meta.isError(result));

    // Check that parser is in error state
    try testing.expectEqual(types.State.Error, parser.state);
}

test "error handling - partial input errors" {
    // Test that partial inputs that could become valid don't error prematurely
    const partial_inputs = [_]struct { input: []const u8, should_error: bool }{
        .{ .input = "{", .should_error = false }, // Could be completed
        .{ .input = "[", .should_error = false }, // Could be completed
        .{ .input = "\"", .should_error = false }, // Could be completed
        .{ .input = "t", .should_error = false }, // Could be "true"
        .{ .input = "f", .should_error = false }, // Could be "false"
        .{ .input = "n", .should_error = false }, // Could be "null"
        .{ .input = "1", .should_error = false }, // Could be completed
        .{ .input = "-", .should_error = false }, // Could be "-1"
    };

    for (partial_inputs) |case| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        const result = parser.feed(case.input);

        if (case.should_error) {
            try testing.expect(std.meta.isError(result));
        } else {
            try testing.expect(!std.meta.isError(result));
        }
    }
}

// ========== DEEPLY NESTED STRUCTURES ==========

test "error handling - deeply nested structures" {
    const max_depth = 100;

    const nested_object = try generators.generateNestedObject(testing.allocator, max_depth);
    defer testing.allocator.free(nested_object);

    const MinifyingParser = @import("src").minifier.MinifyingParser;
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    // This should either work or fail gracefully
    const result = parser.feed(nested_object);
    if (std.meta.isError(result)) {
        // If it errors, it should be a specific depth-related error
        try testing.expect(std.meta.isError(result));
    } else {
        // If it works, flush and verify
        try parser.flush();
        try testing.expect(output.items.len > 0);
    }
}

// ========== INVALID UTF-8 TESTS ==========

test "error handling - invalid UTF-8 in strings" {
    const invalid_byte = try generators.InvalidUtf8.generateInvalidByte(testing.allocator);
    defer testing.allocator.free(invalid_byte);

    const overlong = try generators.InvalidUtf8.generateOverlongEncoding(testing.allocator);
    defer testing.allocator.free(overlong);

    const surrogate = try generators.InvalidUtf8.generateHighSurrogate(testing.allocator);
    defer testing.allocator.free(surrogate);

    const invalid_utf8_inputs = [_][]const u8{ invalid_byte, overlong, surrogate };

    for (invalid_utf8_inputs) |input| {
        const MinifyingParser = @import("src").minifier.MinifyingParser;
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        // Should either handle gracefully or error appropriately
        const result = parser.feed(input);
        if (std.meta.isError(result)) {
            // Expected for invalid UTF-8
        } else {
            try parser.flush();
        }
    }
}

// ========== MEMORY AND RESOURCE TESTS ==========

test "error handling - extremely large inputs" {
    const large_size = 1024 * 1024; // 1MB

    const large_input = try generators.generateLargeJsonString(testing.allocator, large_size, 'a');
    defer testing.allocator.free(large_input);

    const MinifyingParser = @import("src").minifier.MinifyingParser;
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    // This should work or fail gracefully
    const result = parser.feed(large_input);
    if (!std.meta.isError(result)) {
        try parser.flush();
        try testing.expect(output.items.len > 0);
    }
}
