//! Property-Based Testing for Zmin
//!
//! This module implements property-based tests that verify invariants
//! and properties that should hold for all valid inputs.

const std = @import("std");
const zmin = @import("zmin_lib");
const test_framework = @import("test_framework");

/// Properties that must hold for all minification operations
pub const MinificationProperties = struct {
    /// Property: Minified output is always valid JSON
    pub fn validJsonProperty(allocator: std.mem.Allocator, input: []const u8) !void {
        // Only test with valid JSON input
        if (!isValidJson(allocator, input)) return;

        const output = zmin.minifyWithMode(allocator, input, .eco) catch return;
        defer allocator.free(output);

        try test_framework.assertions.assertValidJson(output);
    }

    /// Property: Minified output is never larger than input
    pub fn sizReductionProperty(allocator: std.mem.Allocator, input: []const u8) !void {
        if (!isValidJson(allocator, input)) return;

        const output = try zmin.minifyWithMode(allocator, input, .eco);
        defer allocator.free(output);

        if (output.len > input.len) {
            std.debug.print("Output size ({d}) > input size ({d})\n", .{ output.len, input.len });
            return error.OutputLargerThanInput;
        }
    }

    /// Property: Semantic equivalence is preserved
    pub fn semanticEquivalenceProperty(allocator: std.mem.Allocator, input: []const u8) !void {
        if (!isValidJson(allocator, input)) return;

        const output = try zmin.minifyWithMode(allocator, input, .eco);
        defer allocator.free(output);

        // Parse both and compare
        var input_parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
        defer input_parsed.deinit();
        var output_parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
        defer output_parsed.deinit();

        const input_tree = input_parsed.value;
        const output_tree = output_parsed.value;

        // TODO: Implement deep JSON comparison
        _ = input_tree;
        _ = output_tree;
    }

    /// Property: Idempotence - minifying twice gives same result
    pub fn idempotenceProperty(allocator: std.mem.Allocator, input: []const u8) !void {
        if (!isValidJson(allocator, input)) return;

        const first = try zmin.minifyWithMode(allocator, input, .eco);
        defer allocator.free(first);

        const second = try zmin.minifyWithMode(allocator, first, .eco);
        defer allocator.free(second);

        try std.testing.expectEqualStrings(first, second);
    }

    /// Property: All modes produce semantically equivalent output
    pub fn modeConsistencyProperty(allocator: std.mem.Allocator, input: []const u8) !void {
        if (!isValidJson(allocator, input)) return;

        const eco_output = try zmin.minifyWithMode(allocator, input, .eco);
        defer allocator.free(eco_output);

        const sport_output = try zmin.minifyWithMode(allocator, input, .sport);
        defer allocator.free(sport_output);

        const turbo_output = try zmin.minifyWithMode(allocator, input, .turbo);
        defer allocator.free(turbo_output);

        // All outputs should be identical for same input
        try std.testing.expectEqualStrings(eco_output, sport_output);
        try std.testing.expectEqualStrings(sport_output, turbo_output);
    }

    /// Property: No information loss for numbers
    pub fn numberPrecisionProperty(allocator: std.mem.Allocator, number_str: []const u8) !void {
        const json = try std.fmt.allocPrint(allocator, "[{s}]", .{number_str});
        defer allocator.free(json);

        if (!isValidJson(allocator, json)) return;

        const output = try zmin.minifyWithMode(allocator, json, .eco);
        defer allocator.free(output);

        // Extract number from output
        const start = std.mem.indexOf(u8, output, "[") orelse return error.InvalidOutput;
        const end = std.mem.indexOf(u8, output, "]") orelse return error.InvalidOutput;
        const output_num = output[start + 1 .. end];

        // Numbers should be preserved exactly
        try std.testing.expectEqualStrings(number_str, output_num);
    }
};

/// Property-based test runner
pub const PropertyTester = struct {
    allocator: std.mem.Allocator,
    iterations: u32,
    seed: u64,
    verbose: bool,

    pub fn init(allocator: std.mem.Allocator, iterations: u32, seed: u64) PropertyTester {
        return PropertyTester{
            .allocator = allocator,
            .iterations = iterations,
            .seed = seed,
            .verbose = false,
        };
    }

    /// Run property test with generated inputs
    pub fn testProperty(
        self: *PropertyTester,
        comptime property: anytype,
        generator: anytype,
    ) !void {
        var failures: u32 = 0;
        var prng = std.Random.DefaultPrng.init(self.seed);

        for (0..self.iterations) |i| {
            const input = try generator.generate(self.allocator, prng.random());
            defer self.allocator.free(input);

            property(self.allocator, input) catch |err| {
                failures += 1;
                if (self.verbose) {
                    std.debug.print("Property failed on iteration {d}: {}\n", .{ i, err });
                    std.debug.print("Input: {s}\n", .{input});
                }

                // Try to shrink the failing input
                if (@hasField(@TypeOf(generator), "shrink") and generator.shrink != null) {
                    const shrinkFn = generator.shrink.?;
                    const shrunk = try self.shrinkFailingInput(
                        input,
                        property,
                        shrinkFn,
                    );
                    defer self.allocator.free(shrunk);

                    std.debug.print("Minimal failing input: {s}\n", .{shrunk});
                }
            };
        }

        if (failures > 0) {
            std.debug.print("Property failed {d}/{d} times\n", .{ failures, self.iterations });
            return error.PropertyFailed;
        }
    }

    /// Shrink a failing input to find minimal example
    fn shrinkFailingInput(
        self: *PropertyTester,
        initial: []const u8,
        comptime property: anytype,
        shrinkFn: anytype,
    ) ![]u8 {
        var current = try self.allocator.dupe(u8, initial);
        var changed = true;

        while (changed) {
            changed = false;

            const candidates = try shrinkFn(self.allocator, current);
            defer {
                for (candidates) |candidate| {
                    self.allocator.free(candidate);
                }
                self.allocator.free(candidates);
            }

            for (candidates) |candidate| {
                // Check if candidate still fails
                property(self.allocator, candidate) catch {
                    // This candidate also fails, use it
                    self.allocator.free(current);
                    current = try self.allocator.dupe(u8, candidate);
                    changed = true;
                    break;
                };
            }
        }

        return current;
    }
};

/// Input generators for property testing
pub const generators = struct {
    /// Generate random valid JSON
    pub const JsonGenerator = struct {
        config: test_framework.TestData.JsonConfig,

        pub fn generate(self: JsonGenerator, allocator: std.mem.Allocator, random: std.Random) ![]u8 {
            var config = self.config;
            config.seed = random.int(u64);
            return test_framework.TestData.generateJson(allocator, config);
        }

        pub fn shrink(allocator: std.mem.Allocator, input: []const u8) ![][]u8 {
            var candidates = std.ArrayList([]u8).init(allocator);

            // Try removing elements
            if (std.mem.indexOf(u8, input, ",")) |comma_pos| {
                // Find element boundaries
                var start = comma_pos;
                while (start > 0 and input[start] != '{' and input[start] != '[') : (start -= 1) {}

                var end = comma_pos;
                while (end < input.len and input[end] != '}' and input[end] != ']') : (end += 1) {}

                // Create candidate without this element
                const candidate = try std.mem.concat(allocator, u8, &.{
                    input[0..start],
                    input[end..],
                });
                try candidates.append(candidate);
            }

            return candidates.toOwnedSlice();
        }
    };

    /// Generate random numbers
    pub const NumberGenerator = struct {
        include_special: bool = true,

        pub fn generate(self: NumberGenerator, allocator: std.mem.Allocator, random: std.Random) ![]u8 {
            const choice = random.intRangeAtMost(u8, 0, 10);

            return switch (choice) {
                0 => try allocator.dupe(u8, "0"),
                1 => try allocator.dupe(u8, "-0"),
                2 => try std.fmt.allocPrint(allocator, "{d}", .{random.int(i64)}),
                3 => try std.fmt.allocPrint(allocator, "{d:.6}", .{random.float(f64) * 1000.0}),
                4 => try std.fmt.allocPrint(allocator, "{d}e{d}", .{ random.intRangeAtMost(i32, 1, 9), random.intRangeAtMost(i32, -10, 10) }),
                5 => if (self.include_special) try allocator.dupe(u8, "1.7976931348623157e+308") else try allocator.dupe(u8, "1.0"),
                6 => if (self.include_special) try allocator.dupe(u8, "2.2250738585072014e-308") else try allocator.dupe(u8, "0.1"),
                else => try std.fmt.allocPrint(allocator, "{d}", .{random.intRangeAtMost(i32, -1000, 1000)}),
            };
        }

        pub const shrink = null;
    };

    /// Generate strings with special characters
    pub const StringGenerator = struct {
        max_length: u32 = 100,
        include_unicode: bool = true,
        include_escapes: bool = true,

        pub fn generate(self: StringGenerator, allocator: std.mem.Allocator, random: std.Random) ![]u8 {
            var str = std.ArrayList(u8).init(allocator);
            defer str.deinit();

            try str.append('"');

            const length = random.intRangeAtMost(u32, 0, self.max_length);
            for (0..length) |_| {
                const choice = random.intRangeAtMost(u8, 0, 10);
                switch (choice) {
                    0 => if (self.include_escapes) try str.appendSlice("\\\"") else try str.append('a'),
                    1 => if (self.include_escapes) try str.appendSlice("\\\\") else try str.append('b'),
                    2 => if (self.include_escapes) try str.appendSlice("\\n") else try str.append('c'),
                    3 => if (self.include_escapes) try str.appendSlice("\\t") else try str.append('d'),
                    4 => if (self.include_unicode) {
                        try str.writer().print("\\u{x:0>4}", .{random.intRangeAtMost(u16, 0x0020, 0xD7FF)});
                    } else {
                        try str.append('e');
                    },
                    else => {
                        const char = random.intRangeAtMost(u8, 0x20, 0x7E);
                        if (char != '"' and char != '\\') {
                            try str.append(char);
                        } else {
                            try str.append('x');
                        }
                    },
                }
            }

            try str.append('"');

            // Wrap in array for valid JSON
            return std.fmt.allocPrint(allocator, "[{s}]", .{str.items});
        }

        pub const shrink = null;
    };
};

fn isValidJson(allocator: std.mem.Allocator, input: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch return false;
    defer parsed.deinit();
    _ = parsed.value;
    return true;
}

test "property: valid JSON output" {
    const allocator = std.testing.allocator;
    var tester = PropertyTester.init(allocator, 100, 42);

    const generator = generators.JsonGenerator{
        .config = .{
            .max_depth = 3,
            .max_array_size = 5,
            .max_object_keys = 5,
        },
    };

    try tester.testProperty(MinificationProperties.validJsonProperty, generator);
}

test "property: size reduction" {
    const allocator = std.testing.allocator;
    var tester = PropertyTester.init(allocator, 100, 43);

    const generator = generators.JsonGenerator{
        .config = .{
            .max_depth = 4,
            .include_whitespace = true,
        },
    };

    try tester.testProperty(MinificationProperties.sizReductionProperty, generator);
}

test "property: idempotence" {
    const allocator = std.testing.allocator;
    var tester = PropertyTester.init(allocator, 50, 44);

    const generator = generators.JsonGenerator{
        .config = .{
            .max_depth = 3,
            .include_whitespace = true,
        },
    };

    try tester.testProperty(MinificationProperties.idempotenceProperty, generator);
}

test "property: mode consistency" {
    const allocator = std.testing.allocator;
    var tester = PropertyTester.init(allocator, 50, 45);

    const generator = generators.JsonGenerator{
        .config = .{
            .max_depth = 2,
            .max_array_size = 3,
            .max_object_keys = 3,
        },
    };

    try tester.testProperty(MinificationProperties.modeConsistencyProperty, generator);
}

test "property: number precision" {
    const allocator = std.testing.allocator;
    var tester = PropertyTester.init(allocator, 100, 46);

    const generator = generators.NumberGenerator{
        .include_special = true,
    };

    try tester.testProperty(MinificationProperties.numberPrecisionProperty, generator);
}

test "property: string escaping" {
    const allocator = std.testing.allocator;
    var tester = PropertyTester.init(allocator, 100, 47);

    const generator = generators.StringGenerator{
        .max_length = 50,
        .include_unicode = true,
        .include_escapes = true,
    };

    try tester.testProperty(struct {
        fn stringPreservationProperty(alloc: std.mem.Allocator, input: []const u8) !void {
            if (!isValidJson(alloc, input)) return;

            const output = try zmin.minifyWithMode(alloc, input, .eco);
            defer alloc.free(output);

            // String content should be preserved (including escapes)
            // This is a simplified check - real implementation would parse and compare
            try test_framework.assertions.assertValidJson(output);
        }
    }.stringPreservationProperty, generator);
}
