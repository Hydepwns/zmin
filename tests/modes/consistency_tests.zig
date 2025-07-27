// Mode consistency tests - ensure all modes produce identical output

const std = @import("std");
const testing = std.testing;
const framework = @import("mode_test_framework.zig");

test "all modes produce identical output for common cases" {
    const allocator = testing.allocator;

    for (framework.common_test_cases) |test_case| {
        try framework.testModesConsistency(allocator, test_case);
    }
}

test "all modes handle edge cases identically" {
    const allocator = testing.allocator;

    const edge_cases = [_]framework.ModeTestCase{
        // Very long string
        .{
            .name = "long_string",
            .input = "\"" ++ "x" ** 1000 ++ "\"",
            .expected = "\"" ++ "x" ** 1000 ++ "\"",
        },
        // Deeply nested
        .{
            .name = "deep_nesting",
            .input = "{\"a\":{\"b\":{\"c\":{\"d\":{\"e\":{\"f\":{\"g\":{\"h\":{\"i\":{\"j\":1}}}}}}}}}}",
            .expected = "{\"a\":{\"b\":{\"c\":{\"d\":{\"e\":{\"f\":{\"g\":{\"h\":{\"i\":{\"j\":1}}}}}}}}}}",
        },
        // Large array
        .{
            .name = "large_array",
            .input = "[" ++ "1," ** 99 ++ "1]",
            .expected = "[" ++ "1," ** 99 ++ "1]",
        },
        // Mixed content
        .{
            .name = "mixed_content",
            .input =
            \\{
            \\  "strings": ["hello", "world"],
            \\  "numbers": [1, 2.5, -3, 1e10],
            \\  "booleans": [true, false],
            \\  "null": null,
            \\  "nested": {
            \\    "deep": {
            \\      "value": "found"
            \\    }
            \\  }
            \\}
            ,
            .expected = "{\"strings\":[\"hello\",\"world\"],\"numbers\":[1,2.5,-3,1e10],\"booleans\":[true,false],\"null\":null,\"nested\":{\"deep\":{\"value\":\"found\"}}}",
        },
    };

    for (edge_cases) |test_case| {
        try framework.testModesConsistency(allocator, test_case);
    }
}

test "all modes handle special characters" {
    const allocator = testing.allocator;

    const special_cases = [_]framework.ModeTestCase{
        .{
            .name = "escape_sequences",
            .input = "\"\\\" \\\\ \\/ \\b \\f \\n \\r \\t\"",
            .expected = "\"\\\" \\\\ \\/ \\b \\f \\n \\r \\t\"",
        },
        .{
            .name = "unicode_escapes",
            .input = "\"\\u0048\\u0065\\u006c\\u006c\\u006f \\u4e16\\u754c\"",
            .expected = "\"\\u0048\\u0065\\u006c\\u006c\\u006f \\u4e16\\u754c\"",
        },
        .{
            .name = "emoji",
            .input = "{\"emoji\":\"😀🎉🚀\",\"text\":\"Hello\"}",
            .expected = "{\"emoji\":\"😀🎉🚀\",\"text\":\"Hello\"}",
        },
    };

    for (special_cases) |test_case| {
        try framework.testModesConsistency(allocator, test_case);
    }
}

test "all modes handle whitespace variations" {
    const allocator = testing.allocator;

    const whitespace_cases = [_]framework.ModeTestCase{
        .{
            .name = "no_whitespace",
            .input = "{\"a\":1,\"b\":2}",
            .expected = "{\"a\":1,\"b\":2}",
        },
        .{
            .name = "spaces_only",
            .input = "{ \"a\" : 1 , \"b\" : 2 }",
            .expected = "{\"a\":1,\"b\":2}",
        },
        .{
            .name = "tabs_only",
            .input = "{\t\"a\"\t:\t1\t,\t\"b\"\t:\t2\t}",
            .expected = "{\"a\":1,\"b\":2}",
        },
        .{
            .name = "newlines_only",
            .input = "{\n\"a\"\n:\n1\n,\n\"b\"\n:\n2\n}",
            .expected = "{\"a\":1,\"b\":2}",
        },
        .{
            .name = "mixed_whitespace",
            .input = "{ \t\n\r\"a\" \t\n\r: \t\n\r1 \t\n\r, \t\n\r\"b\" \t\n\r: \t\n\r2 \t\n\r}",
            .expected = "{\"a\":1,\"b\":2}",
        },
    };

    for (whitespace_cases) |test_case| {
        try framework.testModesConsistency(allocator, test_case);
    }
}

test "all modes handle number formats" {
    const allocator = testing.allocator;

    const number_cases = [_]framework.ModeTestCase{
        .{
            .name = "integers",
            .input = "[0, 1, -1, 123, -456]",
            .expected = "[0,1,-1,123,-456]",
        },
        .{
            .name = "decimals",
            .input = "[0.0, 1.5, -2.7, 123.456]",
            .expected = "[0.0,1.5,-2.7,123.456]",
        },
        .{
            .name = "scientific",
            .input = "[1e0, 1e10, 1e-10, 1.23e45, -6.78e-90]",
            .expected = "[1e0,1e10,1e-10,1.23e45,-6.78e-90]",
        },
        .{
            .name = "special_floats",
            .input = "[0.000000000001, 999999999999999999999]",
            .expected = "[0.000000000001,999999999999999999999]",
        },
    };

    for (number_cases) |test_case| {
        try framework.testModesConsistency(allocator, test_case);
    }
}
