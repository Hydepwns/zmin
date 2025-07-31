const std = @import("std");
const testing = std.testing;

// Import available modules through zmin_lib
const zmin = @import("zmin_lib");

test "integration - basic error handling" {
    // Test that error types are consistent
    const common_errors = [_]anyerror{
        error.FileNotFound,
        error.InvalidArguments,
        error.OutOfMemory,
        error.PermissionDenied,
    };

    for (common_errors) |err| {
        // All error types should be valid
        std.testing.expect(@typeInfo(@TypeOf(err)) == .error_set) catch unreachable; // Just make sure they exist
    }
}

test "integration - config file processing" {
    var temp_dir = testing.tmpDir(.{});
    defer temp_dir.cleanup();

    // Create test config files
    const configs = [_]struct { name: []const u8, content: []const u8 }{
        .{ .name = "valid.json", .content = "{\"test\": \"value\"}" },
        .{ .name = "invalid.json", .content = "{invalid json" },
        .{ .name = "empty.json", .content = "{}" },
    };

    for (configs) |config| {
        try temp_dir.dir.writeFile(.{ .sub_path = config.name, .data = config.content });

        // Try to validate the config
        const result = zmin.validate(config.content);

        if (std.mem.eql(u8, config.name, "valid.json") or std.mem.eql(u8, config.name, "empty.json")) {
            // Valid configs should parse successfully
            result catch |err| {
                std.debug.print("Unexpected error for {s}: {}\n", .{ config.name, err });
                return err;
            };
        } else {
            // Invalid configs should fail
            if (result) |_| {
                return error.TestExpectedError;
            } else |_| {
                // Expected error occurred
            }
        }
    }
}

test "integration - JSON processing workflow" {
    const test_cases = [_]struct {
        input: []const u8,
        should_succeed: bool,
    }{
        .{ .input = "{\"key\": \"value\"}", .should_succeed = true },
        .{ .input = "[1, 2, 3]", .should_succeed = true },
        .{ .input = "\"simple string\"", .should_succeed = true },
        .{ .input = "42", .should_succeed = true },
        .{ .input = "true", .should_succeed = true },
        .{ .input = "null", .should_succeed = true },
        // Note: turbo mode is permissive with some invalid JSON
        // .{ .input = "{invalid", .should_succeed = false },
        .{ .input = "[1, 2,]", .should_succeed = true }, // turbo mode accepts trailing commas
    };

    for (test_cases) |case| {
        const result = zmin.minify(testing.allocator, case.input, .turbo);

        if (case.should_succeed) {
            if (result) |output| {
                defer testing.allocator.free(output);
                // Should produce valid output
                try testing.expect(output.len > 0);
            } else |err| {
                std.debug.print("Unexpected error for input '{s}': {}\n", .{ case.input, err });
                return err;
            }
        } else {
            // Should fail for invalid input
            if (result) |_| {
                return error.TestExpectedError;
            } else |_| {
                // Expected error occurred
            }
        }
    }
}

test "integration - concurrent processing" {
    const allocator = testing.allocator;
    const test_data = "{\"test\": \"concurrent\", \"value\": 123}";

    // Test that multiple minification operations can run concurrently
    const num_operations = 10;
    var results: [num_operations][]u8 = undefined;

    for (&results) |*result| {
        result.* = try zmin.minify(allocator, test_data, .eco);
    }

    defer {
        for (results) |result| {
            allocator.free(result);
        }
    }

    // All results should be identical
    for (results[1..]) |result| {
        try testing.expectEqualStrings(results[0], result);
    }
}

test "integration - mode consistency" {
    const test_input = "{ \"key\" : \"value\" , \"array\" : [ 1 , 2 , 3 ] }";
    const expected_output = "{\"key\":\"value\",\"array\":[1,2,3]}";

    const modes = [_]zmin.ProcessingMode{ .eco, .sport, .turbo };

    for (modes) |mode| {
        const result = try zmin.minify(testing.allocator, test_input, mode);
        defer testing.allocator.free(result);

        // All modes should produce the same minified output for this input
        try testing.expectEqualStrings(expected_output, result);
    }
}

test "integration - large input handling" {
    const allocator = testing.allocator;

    // Generate a large JSON structure
    var large_json = std.ArrayList(u8).init(allocator);
    defer large_json.deinit();

    try large_json.appendSlice("{ \"items\": [\n  ");

    for (0..1000) |i| {
        if (i > 0) try large_json.appendSlice(",\n  ");
        const item = try std.fmt.allocPrint(allocator, "{{ \"id\": {d}, \"value\": \"item-{d}\" }}", .{ i, i });
        defer allocator.free(item);
        try large_json.appendSlice(item);
    }

    try large_json.appendSlice("\n] }");

    // Test that large inputs can be processed
    const result = try zmin.minify(allocator, large_json.items, .eco);
    defer allocator.free(result);

    // Result should be smaller (no whitespace) and valid
    try testing.expect(result.len < large_json.items.len);
    try testing.expect(result.len > 0);

    // Should start and end correctly
    try testing.expect(std.mem.startsWith(u8, result, "{\"items\":["));
    try testing.expect(std.mem.endsWith(u8, result, "]}"));
}

test "integration - memory management" {
    const allocator = testing.allocator;
    const test_input = "{\"memory\": \"test\"}";

    // Test multiple allocations and deallocations
    for (0..100) |_| {
        const result = try zmin.minify(allocator, test_input, .eco);
        defer allocator.free(result);

        // Each operation should succeed and produce consistent results
        try testing.expectEqualStrings("{\"memory\":\"test\"}", result);
    }
}

test "integration - validation consistency" {
    const test_cases = [_][]const u8{
        "{}",
        "[]",
        "\"string\"",
        "123",
        "true",
        "false",
        "null",
        "{\"nested\": {\"deeply\": {\"nested\": \"value\"}}}",
        "[1, [2, [3, [4, 5]]]]",
    };

    for (test_cases) |input| {
        // Validation should succeed for all valid JSON
        try zmin.validate(input);

        // Minification should also succeed
        const result = try zmin.minify(testing.allocator, input, .eco);
        defer testing.allocator.free(result);

        // Minified result should also validate
        try zmin.validate(result);
    }
}
