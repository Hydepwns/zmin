const std = @import("std");
const testing = std.testing;

// Import helper modules
const helpers = @import("test_helpers");
const generators = @import("test_data_generators.zig");
const assertions = @import("assertion_helpers");

// ========== BOUNDARY VALUE TESTS ==========

test "edge case - empty and whitespace inputs" {
    // Empty input
    try helpers.testMinify("", "");

    // Whitespace-only inputs
    for (generators.TestPatterns.whitespace_only) |input| {
        try helpers.testMinify(input, "");
    }
}

test "edge case - minimal valid JSON" {
    const test_cases = [_]helpers.TestCase{
        .{ .input = "0", .expected = "0" },
        .{ .input = "\"\"", .expected = "\"\"" },
        .{ .input = "{}", .expected = "{}" },
        .{ .input = "[]", .expected = "[]" },
        .{ .input = "true", .expected = "true" },
        .{ .input = "false", .expected = "false" },
        .{ .input = "null", .expected = "null" },
    };
    try helpers.runTestCases(&test_cases);
}

// ========== EXTREME NESTING TESTS ==========

test "edge case - maximum safe nesting depth" {
    const max_depth = 32; // Should match context_stack size

    const nested_object = try generators.generateNestedObject(testing.allocator, max_depth);
    defer testing.allocator.free(nested_object);

    // Generate expected output (should be identical for valid nesting)
    const expected = try generators.generateNestedObject(testing.allocator, max_depth);
    defer testing.allocator.free(expected);

    try helpers.testMinify(nested_object, expected);
}

test "edge case - mixed nesting with arrays and objects" {
    try helpers.testMinify("[{\"a\":[{\"b\":{\"c\":[1,2,3]}}]}]", "[{\"a\":[{\"b\":{\"c\":[1,2,3]}}]}]");
}

// ========== NUMERIC EDGE CASES ==========

test "edge case - extreme numbers" {
    const test_cases = [_]helpers.TestCase{
        .{ .input = "0", .expected = "0" },
        .{ .input = "-0", .expected = "-0" },
        .{ .input = "9223372036854775807", .expected = "9223372036854775807" }, // Max i64
        .{ .input = "-9223372036854775808", .expected = "-9223372036854775808" }, // Min i64
        .{ .input = "1.7976931348623157e+308", .expected = "1.7976931348623157e+308" }, // Max f64
        .{ .input = "2.2250738585072014e-308", .expected = "2.2250738585072014e-308" }, // Min f64
        .{ .input = "1e-100", .expected = "1e-100" },
        .{ .input = "1e+100", .expected = "1e+100" },
        .{ .input = "0.000000000000001", .expected = "0.000000000000001" },
        .{ .input = "1000000000000000", .expected = "1000000000000000" },
    };
    try helpers.runTestCases(&test_cases);
}

// ========== STRING EDGE CASES ==========

test "edge case - special characters in strings" {
    const test_cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "\" \"", .expected = "\" \"" }, // Single space
        .{ .input = "\"\\t\\n\\r\"", .expected = "\"\\t\\n\\r\"" }, // Common escapes
        .{ .input = "\"\\/\"", .expected = "\"\\/\"" }, // Escaped slash
        .{ .input = "\"\\\"\"", .expected = "\"\\\"\"" }, // Escaped quote
        .{ .input = "\"\\\\\"", .expected = "\"\\\\\"" }, // Escaped backslash
        .{ .input = "\"\\u0000\"", .expected = "\"\\u0000\"" }, // Null character
        .{ .input = "\"\\u001F\"", .expected = "\"\\u001F\"" }, // Control character
        .{ .input = "\"\\u0020\"", .expected = "\"\\u0020\"" }, // Space as unicode
        .{ .input = "\"\\uFFFF\"", .expected = "\"\\uFFFF\"" }, // Max BMP character
    };

    for (test_cases) |case| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(case.input);
        try parser.flush();

        try testing.expectEqualStrings(case.expected, output.items);
    }
}

test "edge case - long strings" {
    const lengths = [_]usize{ 1024, 4096, 8192, 16384 };

    for (lengths) |length| {
        var input = std.ArrayList(u8).init(testing.allocator);
        defer input.deinit();

        try input.append('"');
        for (0..length) |i| {
            try input.append(@intCast('a' + (i % 26)));
        }
        try input.append('"');

        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(input.items);
        try parser.flush();

        try testing.expectEqualStrings(input.items, output.items);
    }
}

// ========== WHITESPACE HANDLING ==========

test "edge case - extensive whitespace variations" {
    const test_cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = " { } ", .expected = "{}" },
        .{ .input = "\n[\n]\n", .expected = "[]" },
        .{ .input = "\t\r\n {\t\r\n \"key\"\t\r\n :\t\r\n \"value\"\t\r\n }\t\r\n ", .expected = "{\"key\":\"value\"}" },
        .{ .input = "   [   1   ,   2   ,   3   ]   ", .expected = "[1,2,3]" },
        .{ .input = "{ \"a\" : [ 1 , 2 ] , \"b\" : { \"c\" : 3 } }", .expected = "{\"a\":[1,2],\"b\":{\"c\":3}}" },
    };

    for (test_cases) |case| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(case.input);
        try parser.flush();

        try testing.expectEqualStrings(case.expected, output.items);
    }
}

// ========== COLLECTION EDGE CASES ==========

test "edge case - large arrays" {
    const sizes = [_]usize{ 100, 1000, 5000 };

    for (sizes) |size| {
        const input = try generators.generateLargeArray(testing.allocator, size);
        defer testing.allocator.free(input);

        // For large arrays, we can't easily predict the exact output format,
        // so we'll test that it processes without error and produces reasonable output
        const MinifyingParser = @import("src").minifier.MinifyingParser;
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(input);
        try parser.flush();

        // Verify basic structure
        try assertions.expectJsonStructure(output.items, '[', ']');
        try assertions.expectMinified(output.items);
    }
}

test "edge case - large objects" {
    const sizes = [_]usize{ 50, 100, 500 };

    for (sizes) |size| {
        const input = try generators.generateLargeObject(testing.allocator, size);
        defer testing.allocator.free(input);

        const MinifyingParser = @import("src").minifier.MinifyingParser;
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(input);
        try parser.flush();

        // Verify basic structure
        try assertions.expectJsonStructure(output.items, '{', '}');
        try assertions.expectMinified(output.items);
    }
}

// ========== MEMORY BOUNDARY TESTS ==========

test "edge case - buffer boundary conditions" {
    const test_input = "{\"key\":\"value\",\"array\":[1,2,3,true,false,null],\"nested\":{\"inner\":\"data\"}}";
    const expected = "{\"key\":\"value\",\"array\":[1,2,3,true,false,null],\"nested\":{\"inner\":\"data\"}}";

    try helpers.testBoundaryChunking(test_input, expected, &generators.TestPatterns.chunk_sizes);
}

// ========== UNICODE EDGE CASES ==========

test "edge case - unicode boundary conditions" {
    const test_cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "\"\\u0000\"", .expected = "\"\\u0000\"" }, // Null
        .{ .input = "\"\\u007F\"", .expected = "\"\\u007F\"" }, // DEL
        .{ .input = "\"\\u0080\"", .expected = "\"\\u0080\"" }, // First non-ASCII
        .{ .input = "\"\\u00FF\"", .expected = "\"\\u00FF\"" }, // ÿ
        .{ .input = "\"\\u0100\"", .expected = "\"\\u0100\"" }, // Ā
        .{ .input = "\"\\u07FF\"", .expected = "\"\\u07FF\"" }, // ߿
        .{ .input = "\"\\u0800\"", .expected = "\"\\u0800\"" }, // ࠀ
        .{ .input = "\"\\uD7FF\"", .expected = "\"\\uD7FF\"" }, // 힟 (last before surrogates)
        .{ .input = "\"\\uE000\"", .expected = "\"\\uE000\"" }, //
        .{ .input = "\"\\uFFFD\"", .expected = "\"\\uFFFD\"" }, // � (replacement character)
        .{ .input = "\"\\uFFFE\"", .expected = "\"\\uFFFE\"" }, // Non-character
        .{ .input = "\"\\uFFFF\"", .expected = "\"\\uFFFF\"" }, // Non-character
    };

    for (test_cases) |case| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(case.input);
        try parser.flush();

        try testing.expectEqualStrings(case.expected, output.items);
    }
}
