//! Regression Test Suite
//!
//! This module contains tests for previously fixed bugs to ensure they
//! don't reappear in future changes.

const std = @import("std");
const zmin = @import("zmin_lib");
const test_framework = @import("../test_framework.zig");

/// Regression test case structure
const RegressionTest = struct {
    /// Issue ID or description
    issue: []const u8,
    /// Date when the issue was fixed
    fixed_date: []const u8,
    /// Input that triggered the bug
    input: []const u8,
    /// Expected output (null if should error)
    expected_output: ?[]const u8,
    /// Expected error (null if should succeed)
    expected_error: ?anyerror,
    /// Modes affected
    affected_modes: []const zmin.ProcessingMode,
    /// Description of the issue
    description: []const u8,
};

/// Collection of regression tests
const regression_tests = [_]RegressionTest{
    .{
        .issue = "#001",
        .fixed_date = "2025-07-26",
        .input = "{\"a\":1,}",
        .expected_output = null,
        .expected_error = error.TrailingComma,
        .affected_modes = &.{ .eco, .sport, .turbo },
        .description = "Trailing comma in object should be rejected",
    },
    .{
        .issue = "#002",
        .fixed_date = "2025-07-26",
        .input = "[1,2,3,]",
        .expected_output = null,
        .expected_error = error.TrailingComma,
        .affected_modes = &.{ .eco, .sport, .turbo },
        .description = "Trailing comma in array should be rejected",
    },
    .{
        .issue = "#003",
        .fixed_date = "2025-07-26",
        .input = "{\"key\":\"value\\u0000\"}",
        .expected_output = "{\"key\":\"value\\u0000\"}",
        .expected_error = null,
        .affected_modes = &.{ .eco, .sport, .turbo },
        .description = "Null character in string should be preserved",
    },
    .{
        .issue = "#004",
        .fixed_date = "2025-07-26",
        .input = "1.7976931348623157e+308",
        .expected_output = "1.7976931348623157e+308",
        .expected_error = null,
        .affected_modes = &.{ .eco, .sport, .turbo },
        .description = "Maximum double value should be preserved exactly",
    },
    .{
        .issue = "#005",
        .fixed_date = "2025-07-26",
        .input = "{\"a\":\"b\",\"a\":\"c\"}",
        .expected_output = null,
        .expected_error = error.DuplicateKey,
        .affected_modes = &.{ .eco, .sport, .turbo },
        .description = "Duplicate object keys should be rejected",
    },
    .{
        .issue = "#006",
        .fixed_date = "2025-07-26",
        .input = "[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[0]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]",
        .expected_output = null,
        .expected_error = error.DepthLimitExceeded,
        .affected_modes = &.{ .eco, .sport, .turbo },
        .description = "Deeply nested arrays should hit depth limit",
    },
    .{
        .issue = "#007",
        .fixed_date = "2025-07-26",
        .input = "\"\\uD800\"",
        .expected_output = null,
        .expected_error = error.InvalidUnicode,
        .affected_modes = &.{ .eco, .sport, .turbo },
        .description = "Invalid UTF-16 surrogates should be rejected",
    },
    .{
        .issue = "#008",
        .fixed_date = "2025-07-26",
        .input = "{\"emoji\":\"🚀\",\"chinese\":\"你好\"}",
        .expected_output = "{\"emoji\":\"🚀\",\"chinese\":\"你好\"}",
        .expected_error = null,
        .affected_modes = &.{ .eco, .sport, .turbo },
        .description = "UTF-8 characters should be preserved",
    },
    .{
        .issue = "#009",
        .fixed_date = "2025-07-26",
        .input = "{\"slash\":\"\\/\"}",
        .expected_output = "{\"slash\":\"/\"}",
        .expected_error = null,
        .affected_modes = &.{ .eco, .sport, .turbo },
        .description = "Escaped forward slash can be unescaped",
    },
    .{
        .issue = "#010",
        .fixed_date = "2025-07-26",
        .input = "-0",
        .expected_output = "-0",
        .expected_error = null,
        .affected_modes = &.{ .eco, .sport, .turbo },
        .description = "Negative zero should be preserved",
    },
};

test "regression: all fixed issues" {
    const allocator = std.testing.allocator;
    var failures: u32 = 0;

    std.debug.print("\nRunning regression tests for {d} fixed issues...\n", .{regression_tests.len});

    for (regression_tests) |test_case| {
        std.debug.print("\nTesting {s}: {s}\n", .{ test_case.issue, test_case.description });

        for (test_case.affected_modes) |mode| {
            const result = zmin.minifyWithMode(allocator, test_case.input, mode);

            if (test_case.expected_output) |expected| {
                // Should succeed with expected output
                if (result) |output| {
                    defer allocator.free(output);

                    if (!std.mem.eql(u8, output, expected)) {
                        std.debug.print("  ❌ {s} mode: Output mismatch\n", .{@tagName(mode)});
                        std.debug.print("    Expected: {s}\n", .{expected});
                        std.debug.print("    Got:      {s}\n", .{output});
                        failures += 1;
                    } else {
                        std.debug.print("  ✅ {s} mode: Correct output\n", .{@tagName(mode)});
                    }
                } else |err| {
                    std.debug.print("  ❌ {s} mode: Unexpected error: {}\n", .{ @tagName(mode), err });
                    failures += 1;
                }
            } else if (test_case.expected_error) |expected_err| {
                // Should fail with expected error
                if (result) |output| {
                    allocator.free(output);
                    std.debug.print("  ❌ {s} mode: Expected error but succeeded\n", .{@tagName(mode)});
                    failures += 1;
                } else |err| {
                    if (err == expected_err) {
                        std.debug.print("  ✅ {s} mode: Correct error\n", .{@tagName(mode)});
                    } else {
                        std.debug.print("  ❌ {s} mode: Wrong error: expected {}, got {}\n", .{ @tagName(mode), expected_err, err });
                        failures += 1;
                    }
                }
            }
        }
    }

    if (failures > 0) {
        std.debug.print("\n❌ Regression tests failed: {d} failures\n", .{failures});
        return error.RegressionTestsFailed;
    } else {
        std.debug.print("\n✅ All regression tests passed!\n", .{});
    }
}

test "regression: memory safety" {
    const allocator = std.testing.allocator;

    // Test cases that previously caused memory issues
    const memory_regression_cases = [_][]const u8{
        // Empty inputs
        "",
        "   ",
        "\n\n\n",

        // Truncated inputs
        "{",
        "[",
        "\"",
        "{\"a\":",
        "[1,",

        // Large repetitive patterns
        "{" ++ "\"a\":1," ** 1000 ++ "}",
        "[" ++ "1," ** 1000 ++ "]",

        // Mixed valid/invalid
        "[1, 2, {\"valid\": true}, INVALID, 5]",
        "{\"good\": 1, bad, \"ok\": 2}",
    };

    std.debug.print("\nTesting memory safety regression cases...\n", .{});

    for (memory_regression_cases, 0..) |input, i| {
        // Use leak detector
        var leak_detector = test_framework.detectLeaks(allocator).init();
        const test_allocator = leak_detector.allocator();

        // Try to minify (may fail, that's ok)
        const result = zmin.minifyWithMode(test_allocator, input, .eco);
        if (result) |output| {
            test_allocator.free(output);
        } else |_| {
            // Error is fine, we're testing for crashes/leaks
        }

        // Check for leaks
        leak_detector.checkLeaks() catch {
            std.debug.print("  ❌ Memory leak in test case {d}\n", .{i});
            return error.MemoryLeakDetected;
        };
    }

    std.debug.print("  ✅ No memory leaks detected\n", .{});
}

test "regression: performance" {
    const allocator = std.testing.allocator;

    // Test cases that previously had performance issues
    const performance_cases = [_]struct {
        name: []const u8,
        generate_input: fn (std.mem.Allocator) anyerror![]u8,
        min_throughput_mbps: f64,
    }{
        .{
            .name = "Deeply nested objects",
            .generate_input = generateDeeplyNestedJson,
            .min_throughput_mbps = 100.0,
        },
        .{
            .name = "Large array of numbers",
            .generate_input = generateLargeNumberArray,
            .min_throughput_mbps = 500.0,
        },
        .{
            .name = "Many small strings",
            .generate_input = generateManyStrings,
            .min_throughput_mbps = 300.0,
        },
        .{
            .name = "Unicode-heavy content",
            .generate_input = generateUnicodeContent,
            .min_throughput_mbps = 200.0,
        },
    };

    std.debug.print("\nTesting performance regression cases...\n", .{});

    for (performance_cases) |test_case| {
        const input = try test_case.generate_input(allocator);
        defer allocator.free(input);

        const start = std.time.microTimestamp();
        const output = try zmin.minifyWithMode(allocator, input, .turbo);
        defer allocator.free(output);
        const duration_us = std.time.microTimestamp() - start;

        const throughput_mbps = (@as(f64, @floatFromInt(input.len)) / (1024.0 * 1024.0)) /
            (@as(f64, @floatFromInt(duration_us)) / 1_000_000.0);

        if (throughput_mbps < test_case.min_throughput_mbps) {
            std.debug.print("  ❌ {s}: {d:.0} MB/s (below {d:.0} MB/s threshold)\n", .{
                test_case.name,
                throughput_mbps,
                test_case.min_throughput_mbps,
            });
            return error.PerformanceRegression;
        } else {
            std.debug.print("  ✅ {s}: {d:.0} MB/s\n", .{ test_case.name, throughput_mbps });
        }
    }
}

fn generateDeeplyNestedJson(allocator: std.mem.Allocator) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);

    // Create 50 levels of nesting
    for (0..50) |i| {
        try json.writer().print("{{\"level_{d}\":", .{i});
    }

    try json.appendSlice("\"deep\"");

    for (0..50) |_| {
        try json.append('}');
    }

    return json.toOwnedSlice();
}

fn generateLargeNumberArray(allocator: std.mem.Allocator) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);
    try json.append('[');

    for (0..10000) |i| {
        if (i > 0) try json.append(',');
        try json.writer().print("{d}", .{i});
    }

    try json.append(']');
    return json.toOwnedSlice();
}

fn generateManyStrings(allocator: std.mem.Allocator) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);
    try json.append('[');

    for (0..1000) |i| {
        if (i > 0) try json.append(',');
        try json.writer().print("\"string_{d}_with_some_content\"", .{i});
    }

    try json.append(']');
    return json.toOwnedSlice();
}

fn generateUnicodeContent(allocator: std.mem.Allocator) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);
    try json.appendSlice("{");

    const unicode_samples = [_][]const u8{
        "\"emoji\":\"🚀🎉✅❌🔥💯\"",
        "\"chinese\":\"你好世界，这是一个测试\"",
        "\"japanese\":\"こんにちは世界、これはテストです\"",
        "\"korean\":\"안녕하세요 세계, 이것은 테스트입니다\"",
        "\"arabic\":\"مرحبا بالعالم، هذا اختبار\"",
        "\"hebrew\":\"שלום עולם, זה מבחן\"",
        "\"russian\":\"Привет мир, это тест\"",
    };

    for (unicode_samples, 0..) |sample, i| {
        if (i > 0) try json.append(',');
        try json.appendSlice(sample);
    }

    try json.append('}');
    return json.toOwnedSlice();
}

test "regression: edge cases" {
    const allocator = std.testing.allocator;

    // Collection of edge cases that were problematic
    const edge_cases = [_]struct {
        input: []const u8,
        should_succeed: bool,
        description: []const u8,
    }{
        // Number edge cases
        .{ .input = "0", .should_succeed = true, .description = "Zero" },
        .{ .input = "-0", .should_succeed = true, .description = "Negative zero" },
        .{ .input = "1e400", .should_succeed = false, .description = "Number too large" },
        .{ .input = "1e-400", .should_succeed = true, .description = "Very small number" },
        .{ .input = "0.000000000000000000000000000001", .should_succeed = true, .description = "Many decimals" },

        // String edge cases
        .{ .input = "\"\"", .should_succeed = true, .description = "Empty string" },
        .{ .input = "\"\\u0000\"", .should_succeed = true, .description = "Null character" },
        .{ .input = "\"\\\"", .should_succeed = false, .description = "Incomplete escape" },
        .{ .input = "\"\\u\"", .should_succeed = false, .description = "Incomplete unicode" },
        .{ .input = "\"\\u000\"", .should_succeed = false, .description = "Incomplete unicode hex" },

        // Structural edge cases
        .{ .input = "[]", .should_succeed = true, .description = "Empty array" },
        .{ .input = "{}", .should_succeed = true, .description = "Empty object" },
        .{ .input = "[,]", .should_succeed = false, .description = "Array with only comma" },
        .{ .input = "{,}", .should_succeed = false, .description = "Object with only comma" },
        .{ .input = "[1 2]", .should_succeed = false, .description = "Missing comma in array" },

        // Whitespace edge cases
        .{ .input = " \n\r\t{}\n\r\t ", .should_succeed = true, .description = "Whitespace around object" },
        .{ .input = "[\n\n\n]", .should_succeed = true, .description = "Newlines in array" },
        .{ .input = "{\"a\"\n:\n1}", .should_succeed = true, .description = "Newlines in object" },
    };

    std.debug.print("\nTesting edge case regressions...\n", .{});

    for (edge_cases) |test_case| {
        const result = zmin.minifyWithMode(allocator, test_case.input, .eco);

        if (test_case.should_succeed) {
            if (result) |output| {
                allocator.free(output);
                std.debug.print("  ✅ {s}\n", .{test_case.description});
            } else |err| {
                std.debug.print("  ❌ {s}: Unexpected error: {}\n", .{ test_case.description, err });
                return error.EdgeCaseRegression;
            }
        } else {
            if (result) |output| {
                allocator.free(output);
                std.debug.print("  ❌ {s}: Expected error but succeeded\n", .{test_case.description});
                return error.EdgeCaseRegression;
            } else |_| {
                std.debug.print("  ✅ {s}: Correctly rejected\n", .{test_case.description});
            }
        }
    }
}
