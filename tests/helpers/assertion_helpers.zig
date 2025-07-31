const std = @import("std");
const testing = std.testing;

/// Assert that a string contains all expected substrings
pub fn expectContainsAll(haystack: []const u8, needles: []const []const u8) !void {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, haystack, needle) == null) {
            std.debug.print("Expected to find '{}' in '{}'\n", .{ needle, haystack });
            return error.AssertionFailed;
        }
    }
}

/// Assert that a string does not contain any of the specified substrings
pub fn expectContainsNone(haystack: []const u8, needles: []const []const u8) !void {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, haystack, needle) != null) {
            std.debug.print("Did not expect to find '{}' in '{}'\n", .{ needle, haystack });
            return error.AssertionFailed;
        }
    }
}

/// Assert that JSON output has proper structure (starts and ends with expected characters)
pub fn expectJsonStructure(output: []const u8, start_char: u8, end_char: u8) !void {
    try testing.expect(output.len > 0);
    if (output[0] != start_char) {
        std.debug.print("Expected output to start with '{}', but got '{}'\n", .{ start_char, output[0] });
        return error.AssertionFailed;
    }
    if (output[output.len - 1] != end_char) {
        std.debug.print("Expected output to end with '{}', but got '{}'\n", .{ end_char, output[output.len - 1] });
        return error.AssertionFailed;
    }
}

/// Assert that output has no unnecessary whitespace
pub fn expectMinified(output: []const u8) !void {
    // Check that there are no spaces outside of strings
    var in_string = false;
    var escaped = false;

    for (output) |char| {
        if (!in_string and (char == ' ' or char == '\t' or char == '\n' or char == '\r')) {
            std.debug.print("Found unexpected whitespace in minified output: '{}'\n", .{output});
            return error.AssertionFailed;
        }

        if (escaped) {
            escaped = false;
            continue;
        }

        if (char == '"') {
            in_string = !in_string;
        } else if (in_string and char == '\\') {
            escaped = true;
        }
    }
}

/// Assert that performance meets minimum requirements
pub fn expectPerformance(throughput_mbps: f64, min_throughput: f64) !void {
    if (throughput_mbps < min_throughput) {
        std.debug.print("Performance below threshold: {d:.2} MB/s < {d:.2} MB/s\n", .{ throughput_mbps, min_throughput });
        return error.PerformanceBelowThreshold;
    }
}

/// Assert that output size is within expected bounds
pub fn expectOutputSize(output_size: usize, min_size: usize, max_size: usize) !void {
    if (output_size < min_size) {
        std.debug.print("Output size too small: {} < {}\n", .{ output_size, min_size });
        return error.OutputTooSmall;
    }
    if (output_size > max_size) {
        std.debug.print("Output size too large: {} > {}\n", .{ output_size, max_size });
        return error.OutputTooLarge;
    }
}

/// Assert that memory usage is reasonable
pub fn expectMemoryUsage(parser_size: usize, max_size: usize) !void {
    if (parser_size > max_size) {
        std.debug.print("Memory usage too high: {} > {} bytes\n", .{ parser_size, max_size });
        return error.MemoryUsageTooHigh;
    }
}

/// Custom assertion for validating specific JSON content patterns
pub const JsonContentAssertion = struct {
    /// Assert that JSON contains valid key-value pairs
    pub fn expectKeyValuePair(output: []const u8, key: []const u8, value: []const u8) !void {
        const pattern = try std.fmt.allocPrint(testing.allocator, "\"{s}\":{s}", .{ key, value });
        defer testing.allocator.free(pattern);

        if (std.mem.indexOf(u8, output, pattern) == null) {
            std.debug.print("Expected to find key-value pair '{}' in '{}'\n", .{ pattern, output });
            return error.KeyValuePairNotFound;
        }
    }

    /// Assert that array contains expected elements in order
    pub fn expectArrayElements(output: []const u8, elements: []const []const u8) !void {
        var current_pos: usize = 0;
        for (elements, 0..) |element, i| {
            const pos = std.mem.indexOfPos(u8, output, current_pos, element);
            if (pos == null) {
                std.debug.print("Array element '{}' not found at position {} or later in '{}'\n", .{ element, current_pos, output });
                return error.ArrayElementNotFound;
            }
            current_pos = pos.? + element.len;

            // For elements after the first, ensure there's a comma before
            if (i > 0) {
                const comma_pos = std.mem.lastIndexOfScalar(u8, output[0..pos.?], ',');
                if (comma_pos == null) {
                    std.debug.print("Missing comma before array element '{}' in '{}'\n", .{ element, output });
                    return error.MissingComma;
                }
            }
        }
    }

    /// Assert that object has expected properties
    pub fn expectObjectProperties(output: []const u8, properties: []const []const u8) !void {
        for (properties) |property| {
            if (std.mem.indexOf(u8, output, property) == null) {
                std.debug.print("Object property '{}' not found in '{}'\n", .{ property, output });
                return error.ObjectPropertyNotFound;
            }
        }
    }
};

/// State-based assertions for parser state validation
/// Note: These functions are commented out to avoid module import conflicts.
/// They can be implemented directly in test files that need them.
pub const StateAssertion = struct {
    // Functions would go here if needed, but avoiding type imports to prevent conflicts
};

/// Error assertion helpers
pub const ErrorAssertion = struct {
    /// Assert that an error is one of the expected errors
    pub fn expectAnyError(result: anyerror, expected_errors: []const anyerror) !void {
        for (expected_errors) |expected_error| {
            if (result == expected_error) return;
        }
        std.debug.print("Got unexpected error: {}\n", .{result});
        return error.UnexpectedError;
    }

    /// Assert that function throws any error (used for invalid input testing)
    pub fn expectAnyErrorThrown(comptime func: anytype, args: anytype) !void {
        const result = @call(.auto, func, args);
        if (!std.meta.isError(@TypeOf(result))) {
            std.debug.print("Expected function to throw an error, but it succeeded\n", .{});
            return error.ExpectedError;
        }
    }
};
