const std = @import("std");
const testing = std.testing;

// Import helper modules
const helpers = @import("test_helpers.zig");
const generators = @import("test_data_generators.zig");
const assertions = @import("assertion_helpers.zig");

// Import MinifyingParser for remaining tests that need direct access
const MinifyingParser = @import("src").minifier.MinifyingParser;

test "error handling - invalid object key" {
    const invalid_inputs = [_][]const u8{
        "{x}", // Invalid object key (not a string)
        "{1}", // Invalid object key (number)
    };

    for (invalid_inputs) |input| {
        try helpers.testMinifySpecificError(input, error.InvalidObjectKey);
    }
}

test "error handling - invalid escape sequences" {
    try helpers.testMinifySpecificError("{\"key\":\"\\x\"}", error.InvalidEscapeSequence);
}

test "error handling - invalid unicode escape" {
    try helpers.testMinifySpecificError("{\"key\":\"\\u123x\"}", error.InvalidUnicodeEscape);
}

test "error handling - invalid numbers" {
    try helpers.testMinifySpecificError("{\"key\":1e}", error.InvalidNumber);
}

test "error handling - invalid booleans" {
    try helpers.testMinifySpecificError("{\"key\":tr}", error.InvalidTrue);
}

test "error handling - invalid false" {
    try helpers.testMinifySpecificError("{\"key\":fa}", error.InvalidFalse);
}

test "error handling - invalid null" {
    try helpers.testMinifySpecificError("{\"key\":nu}", error.InvalidNull);
}

test "error handling - invalid top level" {
    try helpers.testMinifySpecificError("x", error.InvalidTopLevel);
}

test "error handling - unexpected character" {
    const invalid_inputs = [_][]const u8{
        "{\"key\":truex}", // Invalid character after true
        "{\"key\":falsex}", // Invalid character after false
        "{\"key\":nullx}", // Invalid character after null
    };

    for (invalid_inputs) |input| {
        try helpers.testMinifySpecificError(input, error.UnexpectedCharacter);
    }
}

test "edge cases - empty input" {
    try helpers.testMinify("", "");
}

test "edge cases - single character" {
    try helpers.testMinify(" ", "");
}

test "edge cases - very large strings" {
    var input = std.ArrayList(u8).init(testing.allocator);
    defer input.deinit();

    try input.appendSlice("{\"key\":\"");
    // Add a 10KB string
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        try input.append('a');
    }
    try input.appendSlice("\"}");

    var expected = std.ArrayList(u8).init(testing.allocator);
    defer expected.deinit();

    try expected.appendSlice("{\"key\":\"");
    i = 0;
    while (i < 10000) : (i += 1) {
        try expected.append('a');
    }
    try expected.appendSlice("\"}");

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input.items);
    try parser.flush();

    try testing.expectEqualStrings(expected.items, output.items);
}

test "edge cases - very large numbers" {
    const input = "{\"key\":1234567890123456789012345678901234567890}";
    const expected = "{\"key\":1234567890123456789012345678901234567890}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "edge cases - scientific notation" {
    const input = "{\"key\":1.23e+45,\"key2\":-1.23e-45,\"key3\":1.23E45}";
    const expected = "{\"key\":1.23e+45,\"key2\":-1.23e-45,\"key3\":1.23E45}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "edge cases - unicode surrogate pairs" {
    const input = "{\"key\":\"\\uD800\\uDC00\"}"; // U+10000
    const expected = "{\"key\":\"\\uD800\\uDC00\"}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "edge cases - control characters in strings" {
    const input = "{\"key\":\"\\t\\n\\r\\b\\f\"}";
    const expected = "{\"key\":\"\\t\\n\\r\\b\\f\"}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "edge cases - mixed whitespace" {
    try helpers.testMinify("{\n\t\"key\"\t:\n\"value\"\r\n}", "{\"key\":\"value\"}");
}

test "state machine - deep nesting" {
    const depth = 30;

    const input = try generators.generateNestedObject(testing.allocator, depth);
    defer testing.allocator.free(input);

    const expected = try generators.generateNestedObject(testing.allocator, depth);
    defer testing.allocator.free(expected);

    try helpers.testMinify(input, expected);
}

test "state machine - nesting too deep" {
    const max_depth = 33; // Exceeds typical limit

    const nested_object = try generators.generateNestedObject(testing.allocator, max_depth);
    defer testing.allocator.free(nested_object);

    try helpers.testMinifySpecificError(nested_object, error.NestingTooDeep);
}

test "buffer management - large output" {
    const size = 100000;

    var input = std.ArrayList(u8).init(testing.allocator);
    defer input.deinit();
    try input.appendSlice("{\"key\":");
    const large_string = try generators.generateLargeJsonString(testing.allocator, size, 'a');
    defer testing.allocator.free(large_string);
    try input.appendSlice(large_string);
    try input.append('}');

    var expected = std.ArrayList(u8).init(testing.allocator);
    defer expected.deinit();
    try expected.appendSlice("{\"key\":");
    try expected.appendSlice(large_string);
    try expected.append('}');

    try helpers.testMinify(input.items, expected.items);
}

test "integration - round trip validation" {
    const original = "{\n  \"string\": \"hello world\",\n  \"number\": 123.456,\n  \"boolean\": true,\n  \"null\": null,\n  \"array\": [1, 2, 3],\n  \"object\": {\"nested\": \"value\"}\n}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(original);
    try parser.flush();

    // Verify the output is valid JSON by checking structure
    const minified = output.items;
    try testing.expect(minified.len > 0);
    try testing.expect(minified[0] == '{');
    try testing.expect(minified[minified.len - 1] == '}');

    // Verify all expected values are present
    try testing.expect(std.mem.indexOf(u8, minified, "\"string\":\"hello world\"") != null);
    try testing.expect(std.mem.indexOf(u8, minified, "\"number\":123.456") != null);
    try testing.expect(std.mem.indexOf(u8, minified, "\"boolean\":true") != null);
    try testing.expect(std.mem.indexOf(u8, minified, "\"null\":null") != null);
    try testing.expect(std.mem.indexOf(u8, minified, "\"array\":[1,2,3]") != null);
    try testing.expect(std.mem.indexOf(u8, minified, "\"object\":{\"nested\":\"value\"}") != null);
}

test "state machine - all state transitions" {
    const test_cases = [_][]const u8{
        "{}", // ObjectStart -> ObjectComma -> TopLevel
        "[]", // ArrayStart -> ArrayComma -> TopLevel
        "{\"key\":\"value\"}", // ObjectStart -> ObjectKeyString -> ObjectColon -> String -> ObjectComma -> TopLevel
        "[1,2,3]", // ArrayStart -> ArrayValue -> Number -> ArrayComma -> ArrayValue -> Number -> ArrayComma -> ArrayValue -> Number -> ArrayComma -> TopLevel
        "{\"key\":true}", // ObjectStart -> ObjectKeyString -> ObjectColon -> True -> ObjectComma -> TopLevel
        "{\"key\":false}", // ObjectStart -> ObjectKeyString -> ObjectColon -> False -> ObjectComma -> TopLevel
        "{\"key\":null}", // ObjectStart -> ObjectKeyString -> ObjectColon -> Null -> ObjectComma -> TopLevel
        "{\"key\":123.456}", // ObjectStart -> ObjectKeyString -> ObjectColon -> Number -> NumberDecimal -> Number -> ObjectComma -> TopLevel
        "{\"key\":1e+10}", // ObjectStart -> ObjectKeyString -> ObjectColon -> Number -> NumberExponent -> NumberExponentSign -> NumberExponentSign -> ObjectComma -> TopLevel
    };

    for (test_cases) |input| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(input);
        try parser.flush();

        // Verify output is valid
        try testing.expect(output.items.len > 0);
    }
}

test "state machine - nested state transitions" {
    const input = "{\"outer\":{\"inner\":[1,2,{\"deep\":\"value\"}]}}";
    const expected = "{\"outer\":{\"inner\":[1,2,{\"deep\":\"value\"}]}}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "state machine - context stack operations" {
    const input = "{\"level1\":{\"level2\":{\"level3\":{\"level4\":{\"level5\":\"deep\"}}}}}";
    const expected = "{\"level1\":{\"level2\":{\"level3\":{\"level4\":{\"level5\":\"deep\"}}}}}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "buffer management - output buffer overflow" {
    var input = std.ArrayList(u8).init(testing.allocator);
    defer input.deinit();

    try input.appendSlice("{\"key\":\"");
    // Add a 200KB string to test buffer flushing multiple times
    var i: usize = 0;
    while (i < 200000) : (i += 1) {
        try input.append('a');
    }
    try input.appendSlice("\"}");

    var expected = std.ArrayList(u8).init(testing.allocator);
    defer expected.deinit();

    try expected.appendSlice("{\"key\":\"");
    i = 0;
    while (i < 200000) : (i += 1) {
        try expected.append('a');
    }
    try expected.appendSlice("\"}");

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input.items);
    try parser.flush();

    try testing.expectEqualStrings(expected.items, output.items);
}

test "buffer management - large write bypass" {
    var input = std.ArrayList(u8).init(testing.allocator);
    defer input.deinit();

    try input.appendSlice("{\"key\":\"");
    // Add a 200KB string to test large write bypass
    var i: usize = 0;
    while (i < 200000) : (i += 1) {
        try input.append('a');
    }
    try input.appendSlice("\"}");

    var expected = std.ArrayList(u8).init(testing.allocator);
    defer expected.deinit();

    try expected.appendSlice("{\"key\":\"");
    i = 0;
    while (i < 200000) : (i += 1) {
        try expected.append('a');
    }
    try expected.appendSlice("\"}");

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input.items);
    try parser.flush();

    try testing.expectEqualStrings(expected.items, output.items);
}

test "integration - complex JSON structure" {
    const input =
        \\{
        \\  "string": "hello world",
        \\  "number": 123.456,
        \\  "boolean": true,
        \\  "null": null,
        \\  "array": [1, 2, 3, "string", true, null],
        \\  "object": {
        \\    "nested": "value",
        \\    "array": [1, 2, 3],
        \\    "object": {
        \\      "deep": "nested"
        \\    }
        \\  },
        \\  "mixed": [
        \\    "string",
        \\    123,
        \\    true,
        \\    null,
        \\    {
        \\      "key": "value"
        \\    },
        \\    [1, 2, 3]
        \\  ]
        \\}
    ;

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    const minified = output.items;
    try testing.expect(minified.len > 0);
    try testing.expect(minified[0] == '{');
    try testing.expect(minified[minified.len - 1] == '}');

    // Verify all expected values are present
    try testing.expect(std.mem.indexOf(u8, minified, "\"string\":\"hello world\"") != null);
    try testing.expect(std.mem.indexOf(u8, minified, "\"number\":123.456") != null);
    try testing.expect(std.mem.indexOf(u8, minified, "\"boolean\":true") != null);
    try testing.expect(std.mem.indexOf(u8, minified, "\"null\":null") != null);
    try testing.expect(std.mem.indexOf(u8, minified, "\"array\":[1,2,3,\"string\",true,null]") != null);
    try testing.expect(std.mem.indexOf(u8, minified, "\"object\":{\"nested\":\"value\"") != null);
    try testing.expect(std.mem.indexOf(u8, minified, "\"mixed\":[\"string\",123,true,null") != null);
}

test "integration - streaming processing" {
    const chunks = [_][]const u8{
        "{\n  \"key1\": \"value1\",\n",
        "  \"key2\": \"value2\",\n",
        "  \"key3\": \"value3\"\n}",
    };

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    // Process in chunks
    for (chunks) |chunk| {
        try parser.feed(chunk);
    }
    try parser.flush();

    const expected = "{\"key1\":\"value1\",\"key2\":\"value2\",\"key3\":\"value3\"}";
    try testing.expectEqualStrings(expected, output.items);
}

test "performance - large JSON processing" {
    var input = std.ArrayList(u8).init(testing.allocator);
    defer input.deinit();

    // Create a large JSON object with 1000 key-value pairs
    try input.appendSlice("{\n");
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        if (i > 0) try input.appendSlice(",\n");
        try input.writer().print("  \"key{any}\": \"value{any}\"", .{ i, i });
    }
    try input.appendSlice("\n}");

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    const start_time = std.time.milliTimestamp();
    try parser.feed(input.items);
    try parser.flush();
    const end_time = std.time.milliTimestamp();

    const processing_time = @as(f64, @floatFromInt(end_time - start_time));
    const input_size = @as(f64, @floatFromInt(input.items.len));
    const throughput_mbps = (input_size / 1024.0 / 1024.0) / (processing_time / 1000.0);

    // Verify performance is reasonable (should be > 10 MB/s)
    try testing.expect(throughput_mbps > 10.0);

    // Verify output is valid
    try testing.expect(output.items.len > 0);
    try testing.expect(output.items[0] == '{');
    try testing.expect(output.items[output.items.len - 1] == '}');
}

test "performance - memory usage verification" {
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    // Process a large JSON
    var large_json = std.ArrayList(u8).init(testing.allocator);
    defer large_json.deinit();

    try large_json.appendSlice("{\"key\":\"");
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        try large_json.append('a');
    }
    try large_json.appendSlice("\"}");

    try parser.feed(large_json.items);
    try parser.flush();

    // Verify the parser doesn't crash with large input
    try testing.expect(output.items.len > 0);
}

test "edge cases - all whitespace types" {
    const input = "{\t\"key\"\n:\r\"value\"}";
    const expected = "{\"key\":\"value\"}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "edge cases - unicode characters" {
    const input = "{\"key\":\"\\u0048\\u0065\\u006C\\u006C\\u006F\"}"; // "Hello" in unicode escapes
    const expected = "{\"key\":\"\\u0048\\u0065\\u006C\\u006C\\u006F\"}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "edge cases - all escape sequences" {
    const input = "{\"key\":\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"}";
    const expected = "{\"key\":\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "edge cases - scientific notation variations" {
    const input = "{\"key1\":1e10,\"key2\":1E10,\"key3\":1e+10,\"key4\":1e-10,\"key5\":1.23e+45}";
    const expected = "{\"key1\":1e10,\"key2\":1E10,\"key3\":1e+10,\"key4\":1e-10,\"key5\":1.23e+45}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}
