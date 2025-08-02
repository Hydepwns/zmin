const std = @import("std");
const testing = std.testing;
const MinifyingParser = @import("src").minifier.MinifyingParser;

/// Common test case structure for input/expected pairs
pub const TestCase = struct {
    input: []const u8,
    expected: []const u8,
};

/// Helper function to test a single input/expected pair
pub fn testMinify(input: []const u8, expected: []const u8) !void {
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

/// Helper function to test that input causes an error
pub fn testMinifyError(input: []const u8) !void {
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    const result = parser.feed(input);
    try testing.expect(std.meta.isError(result));
}

/// Helper function to test that input causes a specific error
pub fn testMinifySpecificError(input: []const u8, expected_error: anyerror) !void {
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    const result = parser.feed(input);
    try testing.expectError(expected_error, result);
}

/// Helper function to test chunked input processing
pub fn testMinifyChunked(chunks: []const []const u8, expected: []const u8) !void {
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    for (chunks) |chunk| {
        try parser.feed(chunk);
    }
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

/// Helper function to test single character chunked input
pub fn testMinifySingleChars(input: []const u8, expected: []const u8) !void {
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    for (input) |char| {
        const chunk = [_]u8{char};
        try parser.feed(&chunk);
    }
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

/// Helper function to run multiple test cases
pub fn runTestCases(test_cases: []const TestCase) !void {
    for (test_cases) |case| {
        try testMinify(case.input, case.expected);
    }
}

/// Helper function to run multiple error test cases
pub fn runErrorTestCases(invalid_inputs: []const []const u8) !void {
    for (invalid_inputs) |input| {
        try testMinifyError(input);
    }
}

/// Helper function to test boundary chunking with different chunk sizes
pub fn testBoundaryChunking(input: []const u8, expected: []const u8, chunk_sizes: []const usize) !void {
    for (chunk_sizes) |chunk_size| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        var pos: usize = 0;
        while (pos < input.len) {
            const end = @min(pos + chunk_size, input.len);
            try parser.feed(input[pos..end]);
            pos = end;
        }

        try parser.flush();
        try testing.expectEqualStrings(expected, output.items);
    }
}

/// Performance measurement helper
pub const PerformanceResult = struct {
    processing_time_ms: f64,
    input_size_bytes: usize,
    output_size_bytes: usize,
    throughput_mbps: f64,
};

/// Helper function to measure minification performance
pub fn measurePerformance(input: []const u8) !PerformanceResult {
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    const start_time = std.time.milliTimestamp();
    try parser.feed(input);
    try parser.flush();
    const end_time = std.time.milliTimestamp();

    const processing_time = @as(f64, @floatFromInt(end_time - start_time));
    const input_size = @as(f64, @floatFromInt(input.len));
    const throughput_mbps = (input_size / 1024.0 / 1024.0) / (processing_time / 1000.0);

    return PerformanceResult{
        .processing_time_ms = processing_time,
        .input_size_bytes = input.len,
        .output_size_bytes = output.items.len,
        .throughput_mbps = throughput_mbps,
    };
}

/// Helper to verify output contains expected substrings
pub fn expectContains(output: []const u8, expected_substrings: []const []const u8) !void {
    for (expected_substrings) |substring| {
        try testing.expect(std.mem.indexOf(u8, output, substring) != null);
    }
}

/// Helper to verify JSON structure basics
pub fn expectValidJsonStructure(output: []const u8, start_char: u8, end_char: u8) !void {
    try testing.expect(output.len > 0);
    try testing.expect(output[0] == start_char);
    try testing.expect(output[output.len - 1] == end_char);
}
