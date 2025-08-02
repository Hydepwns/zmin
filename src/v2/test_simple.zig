const std = @import("std");
const v2 = @import("mod.zig");

test "v2 basic functionality" {
    const allocator = std.testing.allocator;

    // Test basic minification
    const input = "{\"name\": \"test\", \"value\": 42}";
    const result = try v2.minify(allocator, input);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
    try std.testing.expect(result.len < input.len); // Should be minified

    std.debug.print("Input: {s}\n", .{input});
    std.debug.print("Output: {s}\n", .{result});
}

test "v2 engine functionality" {
    const allocator = std.testing.allocator;

    var engine = try v2.ZminEngine.init(allocator, .{});
    defer engine.deinit();

    const input = "{\"name\": \"test\", \"value\": 42}";

    // Add minification transformation
    try engine.addTransformation(v2.Transformation.init(.{
        .minify = v2.MinifyConfig{ .remove_whitespace = true },
    }));

    const result = try engine.processToString(allocator, input);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
    try std.testing.expect(result.len < input.len);

    std.debug.print("Engine Input: {s}\n", .{input});
    std.debug.print("Engine Output: {s}\n", .{result});
}

test "v2 benchmark functionality" {
    const allocator = std.testing.allocator;

    const input = "{\"name\": \"test\", \"value\": 42}";
    const result = try v2.benchmark(allocator, input, 10);

    try std.testing.expect(result.iterations == 10);
    try std.testing.expect(result.total_time_ms > 0);
    try std.testing.expect(result.throughput_mbps > 0);

    std.debug.print("Benchmark: {} iterations, {} ms, {d:.2} MB/s\n", .{ result.iterations, result.total_time_ms, result.throughput_mbps });
}
