//! Unified Test Framework for Zmin
//!
//! This module provides common testing utilities, helpers, and patterns
//! used across all test suites in the zmin project.

const std = @import("std");
const builtin = @import("builtin");

/// Test categories for organization
pub const TestCategory = enum {
    unit,
    integration,
    performance,
    fuzz,
    regression,

    pub fn getDescription(self: TestCategory) []const u8 {
        return switch (self) {
            .unit => "Unit tests for individual components",
            .integration => "End-to-end integration tests",
            .performance => "Performance benchmarks and tests",
            .fuzz => "Fuzzing tests for robustness",
            .regression => "Tests for previously fixed issues",
        };
    }
};

/// Test result with detailed information
pub const TestResult = struct {
    name: []const u8,
    category: TestCategory,
    passed: bool,
    duration_ns: u64,
    memory_used: ?u64 = null,
    error_message: ?[]const u8 = null,

    pub fn format(
        self: TestResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const status = if (self.passed) "✅ PASS" else "❌ FAIL";
        const duration_ms = @as(f64, @floatFromInt(self.duration_ns)) / 1_000_000.0;

        try writer.print("{s} {s} ({d:.2}ms)", .{ status, self.name, duration_ms });

        if (self.memory_used) |mem| {
            try writer.print(" [{:.2}]", .{std.fmt.fmtIntSizeBin(mem)});
        }

        if (self.error_message) |msg| {
            try writer.print("\n    Error: {s}", .{msg});
        }
    }
};

/// Test runner with timing and memory tracking
pub const TestRunner = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(TestResult),
    start_time: i128,
    verbose: bool,

    pub fn init(allocator: std.mem.Allocator, verbose: bool) TestRunner {
        return TestRunner{
            .allocator = allocator,
            .results = std.ArrayList(TestResult).init(allocator),
            .start_time = std.time.nanoTimestamp(),
            .verbose = verbose,
        };
    }

    pub fn deinit(self: *TestRunner) void {
        self.results.deinit();
    }

    /// Run a single test with tracking
    pub fn runTest(
        self: *TestRunner,
        name: []const u8,
        category: TestCategory,
        testFn: anytype,
    ) !void {
        if (self.verbose) {
            std.debug.print("Running {s}...", .{name});
        }

        const start = std.time.nanoTimestamp();
        var result = TestResult{
            .name = name,
            .category = category,
            .passed = true,
            .duration_ns = 0,
        };

        // Run the test
        testFn() catch |err| {
            result.passed = false;
            result.error_message = @errorName(err);
        };

        result.duration_ns = @intCast(std.time.nanoTimestamp() - start);

        if (self.verbose) {
            std.debug.print(" {}\n", .{result});
        }

        try self.results.append(result);
    }

    /// Generate test report
    pub fn generateReport(self: *TestRunner, writer: anytype) !void {
        const total_duration = @as(f64, @floatFromInt(std.time.nanoTimestamp() - self.start_time)) / 1_000_000_000.0;

        var passed: u32 = 0;
        var failed: u32 = 0;

        for (self.results.items) |result| {
            if (result.passed) {
                passed += 1;
            } else {
                failed += 1;
            }
        }

        try writer.print("\n📊 Test Results\n", .{});
        try writer.print("==================================================\n", .{});
        try writer.print("Total: {d} | ✅ Passed: {d} | ❌ Failed: {d}\n", .{
            passed + failed,
            passed,
            failed,
        });
        try writer.print("Duration: {d:.2}s\n", .{total_duration});

        if (failed > 0) {
            try writer.print("\nFailed Tests:\n", .{});
            for (self.results.items) |result| {
                if (!result.passed) {
                    try writer.print("  {}\n", .{result});
                }
            }
        }
    }
};

/// Test data generators
pub const TestData = struct {
    /// Generate valid JSON of specified complexity
    pub fn generateJson(allocator: std.mem.Allocator, config: JsonConfig) ![]u8 {
        var json = std.ArrayList(u8).init(allocator);
        errdefer json.deinit();

        var prng = std.Random.DefaultPrng.init(config.seed);
        try generateJsonValue(&json, config, 0, prng.random());

        return json.toOwnedSlice();
    }

    pub const JsonConfig = struct {
        max_depth: u32 = 5,
        max_array_size: u32 = 10,
        max_object_keys: u32 = 10,
        max_string_length: u32 = 50,
        include_whitespace: bool = true,
        include_unicode: bool = false,
        seed: u64 = 0,
    };

    fn generateJsonValue(
        json: *std.ArrayList(u8),
        config: JsonConfig,
        depth: u32,
        random: std.Random,
    ) std.mem.Allocator.Error!void {
        if (depth >= config.max_depth) {
            // Generate simple value at max depth
            try json.appendSlice("\"leaf\"");
            return;
        }

        const value_type = random.intRangeAtMost(u8, 0, 6);
        switch (value_type) {
            0 => try json.appendSlice("null"),
            1 => try json.appendSlice(if (random.boolean()) "true" else "false"),
            2 => try json.writer().print("{d}", .{random.int(i32)}),
            3 => try json.writer().print("{d:.6}", .{random.float(f64) * 1000.0}),
            4 => try generateJsonString(json, config, random),
            5 => try generateJsonArray(json, config, depth + 1, random),
            6 => try generateJsonObject(json, config, depth + 1, random),
            else => unreachable,
        }
    }

    fn generateJsonString(
        json: *std.ArrayList(u8),
        config: JsonConfig,
        random: std.Random,
    ) !void {
        try json.append('"');

        const length = random.intRangeAtMost(u32, 0, config.max_string_length);
        for (0..length) |_| {
            if (config.include_unicode and random.intRangeAtMost(u8, 0, 10) == 0) {
                // Include some Unicode
                try json.writer().print("\\u{x:0>4}", .{random.intRangeAtMost(u16, 0x0020, 0x007E)});
            } else {
                // Regular ASCII
                const char = random.intRangeAtMost(u8, 0x20, 0x7E);
                switch (char) {
                    '"' => try json.appendSlice("\\\""),
                    '\\' => try json.appendSlice("\\\\"),
                    else => try json.append(char),
                }
            }
        }

        try json.append('"');
    }

    fn generateJsonArray(
        json: *std.ArrayList(u8),
        config: JsonConfig,
        depth: u32,
        random: std.Random,
    ) !void {
        try json.append('[');

        const size = random.intRangeAtMost(u32, 0, config.max_array_size);
        for (0..size) |i| {
            if (i > 0) {
                try json.append(',');
                if (config.include_whitespace) try json.append(' ');
            }
            try generateJsonValue(json, config, depth, random);
        }

        try json.append(']');
    }

    fn generateJsonObject(
        json: *std.ArrayList(u8),
        config: JsonConfig,
        depth: u32,
        random: std.Random,
    ) !void {
        try json.append('{');
        if (config.include_whitespace) try json.append('\n');

        const size = random.intRangeAtMost(u32, 0, config.max_object_keys);
        for (0..size) |i| {
            if (i > 0) {
                try json.append(',');
                if (config.include_whitespace) try json.append('\n');
            }

            // Generate key
            try json.append('"');
            try json.writer().print("key_{d}", .{i});
            try json.append('"');
            try json.append(':');
            if (config.include_whitespace) try json.append(' ');

            // Generate value
            try generateJsonValue(json, config, depth, random);
        }

        if (config.include_whitespace) try json.append('\n');
        try json.append('}');
    }
};

/// Common test assertions
pub const assertions = struct {
    /// Assert that two JSON strings are semantically equivalent
    pub fn assertJsonEqual(expected: []const u8, actual: []const u8) !void {
        // Normalize both JSON strings by removing non-significant whitespace
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();
        
        const normalized_expected = try normalizeJson(allocator, expected);
        defer allocator.free(normalized_expected);
        
        const normalized_actual = try normalizeJson(allocator, actual);
        defer allocator.free(normalized_actual);
        
        try std.testing.expectEqualStrings(normalized_expected, normalized_actual);
    }
    
    /// Normalize JSON by removing insignificant whitespace
    fn normalizeJson(allocator: std.mem.Allocator, json: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        var in_string = false;
        var escape_next = false;
        var i: usize = 0;
        
        while (i < json.len) : (i += 1) {
            const char = json[i];
            
            if (escape_next) {
                try result.append(char);
                escape_next = false;
                continue;
            }
            
            switch (char) {
                '"' => {
                    in_string = !in_string;
                    try result.append(char);
                },
                '\\' => {
                    if (in_string) {
                        escape_next = true;
                    }
                    try result.append(char);
                },
                ' ', '\t', '\n', '\r' => {
                    if (in_string) {
                        try result.append(char);
                    } else {
                        // Skip whitespace outside strings, but preserve structure
                        // Check if we need a space between tokens
                        if (result.items.len > 0 and i + 1 < json.len) {
                            const prev = result.items[result.items.len - 1];
                            const next = json[i + 1];
                            
                            // Add space between value tokens that need separation
                            if ((isAlphaNumeric(prev) and isAlphaNumeric(next)) or
                                (prev == '"' and next == '"') or
                                (isDigit(prev) and isDigit(next)))
                            {
                                try result.append(' ');
                            }
                        }
                    }
                },
                else => {
                    try result.append(char);
                },
            }
        }
        
        return result.toOwnedSlice();
    }
    
    fn isAlphaNumeric(c: u8) bool {
        return (c >= 'a' and c <= 'z') or
               (c >= 'A' and c <= 'Z') or
               (c >= '0' and c <= '9') or
               c == '_';
    }
    
    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    /// Assert that a string is valid JSON
    pub fn assertValidJson(json: []const u8) !void {
        // TODO: Implement JSON validation
        _ = json;
    }

    /// Assert memory usage is within bounds
    pub fn assertMemoryUsage(actual: u64, max_expected: u64) !void {
        if (actual > max_expected) {
            std.debug.print("Memory usage {d} exceeds maximum {d}\n", .{ actual, max_expected });
            return error.ExcessiveMemoryUsage;
        }
    }

    /// Assert performance meets threshold
    pub fn assertPerformance(throughput_mbps: f64, min_expected: f64) !void {
        if (throughput_mbps < min_expected) {
            std.debug.print("Throughput {d:.2} MB/s below minimum {d:.2} MB/s\n", .{
                throughput_mbps,
                min_expected,
            });
            return error.PerformanceBelowThreshold;
        }
    }
};

/// Test fixtures and sample data
pub const fixtures = struct {
    pub const simple_json =
        \\{
        \\  "name": "test",
        \\  "value": 42,
        \\  "active": true
        \\}
    ;

    pub const simple_json_minified =
        \\{"name":"test","value":42,"active":true}
    ;

    pub const nested_json =
        \\{
        \\  "user": {
        \\    "id": 123,
        \\    "profile": {
        \\      "name": "John Doe",
        \\      "tags": ["developer", "tester"]
        \\    }
        \\  }
        \\}
    ;

    pub const edge_cases = [_][]const u8{
        "{}",
        "[]",
        "null",
        "true",
        "false",
        "0",
        "-1.23e-4",
        "\"\"",
        "\"\\\"\\\\\\b\\f\\n\\r\\t\"",
        "[[[[[]]]]]]",
    };
};

/// Memory leak detector for tests
pub fn detectLeaks(allocator: std.mem.Allocator) type {
    return struct {
        const Self = @This();

        wrapped_allocator: std.mem.Allocator,
        allocation_count: usize = 0,

        pub fn init() Self {
            return Self{
                .wrapped_allocator = allocator,
            };
        }

        pub fn getAllocator(self: *Self) std.mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .free = free,
                    .remap = remap,
                },
            };
        }

        fn alloc(ctx: *anyopaque, len: usize, log2_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const result = self.wrapped_allocator.rawAlloc(len, log2_align, ret_addr);
            if (result != null) {
                self.allocation_count += 1;
            }
            return result;
        }

        fn resize(ctx: *anyopaque, buf: []u8, log2_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.wrapped_allocator.rawResize(buf, log2_align, new_len, ret_addr);
        }

        fn free(ctx: *anyopaque, buf: []u8, log2_align: std.mem.Alignment, ret_addr: usize) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.wrapped_allocator.rawFree(buf, log2_align, ret_addr);
            self.allocation_count -= 1;
        }

        fn remap(ctx: *anyopaque, buf: []u8, log2_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.wrapped_allocator.rawRemap(buf, log2_align, new_len, ret_addr);
        }

        pub fn checkLeaks(self: Self) !void {
            if (self.allocation_count != 0) {
                std.debug.print("Memory leak detected: {d} allocations not freed\n", .{self.allocation_count});
                return error.MemoryLeak;
            }
        }
    };
}
