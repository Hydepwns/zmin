const std = @import("std");
const testing = std.testing;

// Import helper modules
const helpers = @import("test_helpers.zig");
const generators = @import("test_data_generators.zig");
const assertions = @import("assertion_helpers.zig");

// Import utils for utility function tests
const utils = @import("src/minifier/utils.zig");

// ========== BASIC FUNCTIONALITY TESTS ==========

test "minifier - basic functionality" {
    try helpers.testMinify("{\"test\":\"value\"}", "{\"test\":\"value\"}");
}

test "minifier - whitespace removal" {
    try helpers.testMinify("{\n  \"test\": \"value\",\n  \"number\": 42\n}", "{\"test\":\"value\",\"number\":42}");
}

test "minifier - empty structures" {
    const test_cases = [_]helpers.TestCase{
        .{ .input = "{}", .expected = "{}" },
        .{ .input = "[]", .expected = "[]" },
    };
    try helpers.runTestCases(&test_cases);
}

test "minifier - nested structures" {
    const test_cases = [_]helpers.TestCase{
        .{ .input = "{\n  \"outer\": {\n    \"inner\": \"value\"\n  }\n}", .expected = "{\"outer\":{\"inner\":\"value\"}}" },
        .{ .input = "[\n  \"string\",\n  42,\n  true,\n  null\n]", .expected = "[\"string\",42,true,null]" },
    };
    try helpers.runTestCases(&test_cases);
}

// ========== NUMBER HANDLING TESTS ==========

test "minifier - integer numbers" {
    const test_cases = [_]helpers.TestCase{
        .{ .input = "0", .expected = "0" },
        .{ .input = "42", .expected = "42" },
        .{ .input = "-17", .expected = "-17" },
        .{ .input = "1000", .expected = "1000" },
    };
    try helpers.runTestCases(&test_cases);
}

test "minifier - decimal numbers" {
    const test_cases = [_]helpers.TestCase{
        .{ .input = "3.14", .expected = "3.14" },
        .{ .input = "0.5", .expected = "0.5" },
        .{ .input = "-2.718", .expected = "-2.718" },
    };
    try helpers.runTestCases(&test_cases);
}

test "minifier - scientific notation" {
    const test_cases = [_]helpers.TestCase{
        .{ .input = "1e10", .expected = "1e10" },
        .{ .input = "1E10", .expected = "1E10" },
        .{ .input = "1e+10", .expected = "1e+10" },
        .{ .input = "1e-10", .expected = "1e-10" },
        .{ .input = "3.14e2", .expected = "3.14e2" },
    };
    try helpers.runTestCases(&test_cases);
}

// ========== STRING HANDLING TESTS ==========

test "minifier - basic strings" {
    const test_cases = [_]helpers.TestCase{
        .{ .input = "\"hello\"", .expected = "\"hello\"" },
        .{ .input = "\"\"", .expected = "\"\"" },
        .{ .input = "\"test with spaces\"", .expected = "\"test with spaces\"" },
    };
    try helpers.runTestCases(&test_cases);
}

test "minifier - escaped strings" {
    const test_cases = [_]helpers.TestCase{
        .{ .input = "\"\\\"quoted\\\"\"", .expected = "\"\\\"quoted\\\"\"" },
        .{ .input = "\"line1\\nline2\"", .expected = "\"line1\\nline2\"" },
        .{ .input = "\"tab\\there\"", .expected = "\"tab\\there\"" },
        .{ .input = "\"backslash\\\\\"", .expected = "\"backslash\\\\\"" },
    };
    try helpers.runTestCases(&test_cases);
}

test "minifier - unicode escapes" {
    const test_cases = [_]helpers.TestCase{
        .{ .input = "\"\\u0041\"", .expected = "\"\\u0041\"" },
        .{ .input = "\"\\u00A9\"", .expected = "\"\\u00A9\"" },
        .{ .input = "\"\\u20AC\"", .expected = "\"\\u20AC\"" },
    };
    try helpers.runTestCases(&test_cases);
}

// ========== BOOLEAN AND NULL TESTS ==========

test "minifier - boolean and null values" {
    const test_cases = [_]helpers.TestCase{
        .{ .input = "true", .expected = "true" },
        .{ .input = "false", .expected = "false" },
        .{ .input = "null", .expected = "null" },
    };
    try helpers.runTestCases(&test_cases);
}

// ========== COMPLEX STRUCTURE TESTS ==========

test "minifier - complex nested structure" {
    const input = try generators.generateComplexStructure(testing.allocator);
    defer testing.allocator.free(input);

    const expected = "{\"users\":[{\"id\":1,\"name\":\"John Doe\",\"active\":true,\"metadata\":{\"last_login\":null,\"permissions\":[\"read\",\"write\"]}},{\"id\":2,\"name\":\"Jane Smith\",\"active\":false,\"metadata\":{\"last_login\":\"2023-01-01\",\"permissions\":[\"read\"]}}],\"total\":2}";

    try helpers.testMinify(input, expected);
}

// ========== UTILITY FUNCTION TESTS ==========

test "utils - isWhitespace" {
    try testing.expect(utils.isWhitespace(' '));
    try testing.expect(utils.isWhitespace('\t'));
    try testing.expect(utils.isWhitespace('\n'));
    try testing.expect(utils.isWhitespace('\r'));
    try testing.expect(!utils.isWhitespace('a'));
    try testing.expect(!utils.isWhitespace('0'));
    try testing.expect(!utils.isWhitespace('{'));
}

test "utils - isHexDigit" {
    try testing.expect(utils.isHexDigit('0'));
    try testing.expect(utils.isHexDigit('9'));
    try testing.expect(utils.isHexDigit('a'));
    try testing.expect(utils.isHexDigit('f'));
    try testing.expect(utils.isHexDigit('A'));
    try testing.expect(utils.isHexDigit('F'));
    try testing.expect(!utils.isHexDigit('g'));
    try testing.expect(!utils.isHexDigit('G'));
    try testing.expect(!utils.isHexDigit(' '));
}

// ========== STREAMING/CHUNKED INPUT TESTS ==========

test "minifier - chunked input processing" {
    const chunks = [_][]const u8{ "{", "\"test\"", ":", "\"value\"", "}" };
    const expected = "{\"test\":\"value\"}";

    try helpers.testMinifyChunked(&chunks, expected);
}

test "minifier - single character chunks" {
    const input = "{\"a\":1}";
    const expected = "{\"a\":1}";

    try helpers.testMinifySingleChars(input, expected);
}
