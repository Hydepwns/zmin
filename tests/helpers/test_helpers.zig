const std = @import("std");
const testing = std.testing;
const MinifyingParser = @import("src").minifier.MinifyingParser;

// Import test fixtures
pub const fixtures = @import("test_fixtures.zig");

/// Common test case structure for input/expected pairs
pub const TestCase = fixtures.TestCase;

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

/// Test runner for fixture-based tests
pub const FixtureRunner = struct {
    allocator: std.mem.Allocator,
    verbose: bool = false,
    
    pub fn init(allocator: std.mem.Allocator) FixtureRunner {
        return .{ .allocator = allocator };
    }
    
    /// Run all basic JSON test cases
    pub fn runBasicTests(self: FixtureRunner) !void {
        const all_tests = fixtures.getAllBasicTests();
        
        for (all_tests) |test_case| {
            if (self.verbose) {
                std.debug.print("Running test: {s}\n", .{test_case.name});
            }
            
            testMinify(test_case.input, test_case.expected) catch |err| {
                std.debug.print("Failed test '{s}': {}\n", .{test_case.name, err});
                return err;
            };
        }
    }
    
    /// Run all invalid JSON test cases
    pub fn runInvalidTests(self: FixtureRunner) !void {
        const all_invalid = fixtures.getAllInvalidTests();
        
        for (all_invalid) |invalid_json| {
            if (self.verbose) {
                std.debug.print("Testing invalid JSON: {s}\n", .{invalid_json});
            }
            
            testMinifyError(invalid_json) catch |err| {
                std.debug.print("Failed to reject invalid JSON: {s}\n", .{invalid_json});
                return err;
            };
        }
    }
    
    /// Run performance benchmarks
    pub fn runBenchmarks(self: FixtureRunner) !void {
        const configs = [_]fixtures.BenchmarkConfig{
            fixtures.BenchmarkConfigs.small_input,
            fixtures.BenchmarkConfigs.medium_input,
            fixtures.BenchmarkConfigs.large_input,
        };
        
        for (configs) |config| {
            const input = try fixtures.PerformanceData.generateNumberArray(
                self.allocator, 
                config.input_size / 10  // Approximate size
            );
            defer self.allocator.free(input);
            
            var total_time: f64 = 0;
            for (0..config.iterations) |_| {
                const result = try measurePerformance(input);
                total_time += result.processing_time_ms;
            }
            
            const avg_time = total_time / @as(f64, @floatFromInt(config.iterations));
            const throughput = (@as(f64, @floatFromInt(input.len)) / 1024.0 / 1024.0) / (avg_time / 1000.0);
            
            if (self.verbose) {
                std.debug.print("{s}: {d:.2} MB/s (avg {d:.2}ms)\n", .{
                    config.name,
                    throughput,
                    avg_time,
                });
            }
        }
    }
};

/// Create a test allocator with tracking
pub fn createTestAllocator() std.mem.Allocator {
    return testing.allocator;
}

/// Helper to create JSON test data with specific characteristics
pub const TestDataBuilder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    
    pub fn init(allocator: std.mem.Allocator) TestDataBuilder {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *TestDataBuilder) void {
        self.buffer.deinit();
    }
    
    /// Add whitespace padding
    pub fn withWhitespace(self: *TestDataBuilder, json: []const u8) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        
        for (json) |char| {
            try self.buffer.append(char);
            if (char == ',' or char == ':') {
                try self.buffer.append(' ');
            }
        }
        
        return self.buffer.items;
    }
    
    /// Create JSON with specific nesting depth
    pub fn withDepth(self: *TestDataBuilder, depth: usize) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        
        for (0..depth) |_| {
            try self.buffer.appendSlice("{\"a\":");
        }
        try self.buffer.append('1');
        for (0..depth) |_| {
            try self.buffer.append('}');
        }
        
        return self.buffer.items;
    }
};
