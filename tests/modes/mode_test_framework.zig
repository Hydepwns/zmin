// Mode-specific testing framework

const std = @import("std");
const testing = std.testing;
const modes = @import("modes");
pub const MinifierInterface = @import("minifier_interface").MinifierInterface;

/// Test case for mode comparison
pub const ModeTestCase = struct {
    name: []const u8,
    input: []const u8,
    expected: []const u8,
    modes_to_test: []const modes.ProcessingMode = &[_]modes.ProcessingMode{ .eco, .sport, .turbo },
};

/// Performance test requirements
pub const PerformanceRequirement = struct {
    mode: modes.ProcessingMode,
    min_throughput_mbps: f64,
    max_memory_bytes: usize,
    tolerance_percent: f64 = 10.0,
};

/// Memory scaling test
pub const MemoryScalingTest = struct {
    mode: modes.ProcessingMode,
    file_sizes: []const usize,
    expected_memory_fn: *const fn (usize) usize,
};

/// Test that all modes produce identical output
pub fn testModesConsistency(allocator: std.mem.Allocator, test_case: ModeTestCase) !void {
    var results = std.ArrayList([]u8).init(allocator);
    defer {
        for (results.items) |result| {
            allocator.free(result);
        }
        results.deinit();
    }

    // Run each mode
    for (test_case.modes_to_test) |mode| {
        if (!MinifierInterface.isModeSupported(mode)) {
            continue;
        }

        const result = try MinifierInterface.minifyString(allocator, mode, test_case.input);
        try results.append(result);
    }

    // Verify all results match expected
    for (results.items) |result| {
        try testing.expectEqualStrings(test_case.expected, result);
    }

    // Verify all results are identical
    if (results.items.len > 1) {
        const first = results.items[0];
        for (results.items[1..]) |result| {
            try testing.expectEqualStrings(first, result);
        }
    }
}

/// Test performance requirements for a mode
pub fn testModePerformance(
    allocator: std.mem.Allocator,
    requirement: PerformanceRequirement,
    test_data: []const u8,
) !void {
    if (!MinifierInterface.isModeSupported(requirement.mode)) {
        return;
    }

    var timer = try std.time.Timer.start();
    var peak_memory: usize = 0;

    // Warm up
    _ = try MinifierInterface.minifyString(allocator, requirement.mode, test_data);

    // Measure performance over multiple runs
    const num_runs = 10;
    var total_time: u64 = 0;

    for (0..num_runs) |_| {
        timer.reset();
        const result = try MinifierInterface.minifyString(allocator, requirement.mode, test_data);
        defer allocator.free(result);

        total_time += timer.read();

        // Track memory (simplified - in real implementation would use allocator wrapper)
        const estimated_memory = MinifierInterface.getMemoryRequirement(requirement.mode, test_data.len);
        peak_memory = @max(peak_memory, estimated_memory);
    }

    const avg_time_ns = total_time / num_runs;
    const throughput_mbps = (@as(f64, @floatFromInt(test_data.len)) / @as(f64, @floatFromInt(avg_time_ns))) * 1000.0;

    // Check throughput requirement
    const min_acceptable = requirement.min_throughput_mbps * (1.0 - requirement.tolerance_percent / 100.0);
    try testing.expect(throughput_mbps >= min_acceptable);

    // Check memory requirement
    try testing.expect(peak_memory <= requirement.max_memory_bytes);
}

/// Test memory scaling behavior
pub fn testMemoryScaling(
    _: std.mem.Allocator,
    scaling_test: MemoryScalingTest,
) !void {
    if (!MinifierInterface.isModeSupported(scaling_test.mode)) {
        return;
    }

    for (scaling_test.file_sizes) |size| {
        const memory = MinifierInterface.getMemoryRequirement(scaling_test.mode, size);
        const expected = scaling_test.expected_memory_fn(size);

        // Allow 20% tolerance for memory estimates
        const ratio = @as(f64, @floatFromInt(memory)) / @as(f64, @floatFromInt(expected));
        try testing.expect(ratio >= 0.8 and ratio <= 1.2);
    }
}

/// Generate test JSON of specified size
pub fn generateTestJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    try result.appendSlice("[");

    var current_size: usize = 1;
    var counter: usize = 0;

    while (current_size < target_size - 10) {
        if (counter > 0) {
            try result.appendSlice(",");
            current_size += 1;
        }

        const item = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"value\":\"test{d}\"}}", .{ counter, counter });
        defer allocator.free(item);

        try result.appendSlice(item);
        current_size += item.len;
        counter += 1;
    }

    try result.appendSlice("]");
    return result.toOwnedSlice();
}

/// Common test cases for all modes
pub const common_test_cases = [_]ModeTestCase{
    .{ .name = "empty", .input = "", .expected = "" },
    .{ .name = "null", .input = "null", .expected = "null" },
    .{ .name = "true", .input = "true", .expected = "true" },
    .{ .name = "false", .input = "false", .expected = "false" },
    .{ .name = "number", .input = "123.456", .expected = "123.456" },
    .{ .name = "string", .input = "\"hello\"", .expected = "\"hello\"" },
    .{ .name = "empty_object", .input = "{}", .expected = "{}" },
    .{ .name = "empty_array", .input = "[]", .expected = "[]" },
    .{ .name = "whitespace", .input = "  {  }  ", .expected = "{}" },
    .{ .name = "simple_object", .input = "{\"a\":1}", .expected = "{\"a\":1}" },
    .{ .name = "simple_array", .input = "[1,2,3]", .expected = "[1,2,3]" },
    .{ .name = "nested", .input = 
    \\{
    \\  "a": {
    \\    "b": [1, 2, 3]
    \\  }
    \\}
    , .expected = "{\"a\":{\"b\":[1,2,3]}}" },
    .{ .name = "escaped_string", .input = "\"\\\"hello\\\"\"", .expected = "\"\\\"hello\\\"\"" },
    .{ .name = "unicode", .input = "\"\\u0048\\u0065\\u006C\\u006C\\u006F\"", .expected = "\"\\u0048\\u0065\\u006C\\u006C\\u006F\"" },
    .{ .name = "mixed_whitespace", .input = " \t\n\r{ \t\n\r\"a\" \t\n\r: \t\n\r1 \t\n\r} \t\n\r", .expected = "{\"a\":1}" },
};

/// Performance requirements for each mode
pub const performance_requirements = [_]PerformanceRequirement{
    .{ .mode = .eco, .min_throughput_mbps = 10.0, .max_memory_bytes = 64 * 1024 }, // Relaxed for test env
    .{ .mode = .sport, .min_throughput_mbps = 50.0, .max_memory_bytes = 16 * 1024 * 1024 }, // Relaxed for test env
    .{ .mode = .turbo, .min_throughput_mbps = 100.0, .max_memory_bytes = std.math.maxInt(usize) }, // Relaxed for test env
};
