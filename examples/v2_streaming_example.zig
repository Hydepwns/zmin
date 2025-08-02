const std = @import("std");
const zmin = @import("../src/root.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== zmin v2.0 Streaming Transformation Engine Demo ===\n", .{});

    // Example JSON input
    const input_json =
        \\{
        \\  "name": "John Doe",
        \\  "age": 30,
        \\  "email": "john.doe@example.com",
        \\  "address": {
        \\    "street": "123 Main St",
        \\    "city": "Anytown",
        \\    "country": "USA"
        \\  },
        \\  "hobbies": ["reading", "swimming", "coding"]
        \\}
    ;

    std.debug.print("Input JSON:\n{s}\n", .{input_json});

    // 1. Basic minification
    std.debug.print("\n1. Basic Minification:\n", .{});
    const minified = try zmin.minifyV2(allocator, input_json);
    defer allocator.free(minified);
    std.debug.print("Minified: {s}\n", .{minified});

    // 2. Minification with custom configuration
    std.debug.print("\n2. Custom Minification:\n", .{});
    var engine = try zmin.v2.ZminEngine.init(allocator, .{});
    defer engine.deinit();

    try engine.addTransformation(zmin.v2.Transformation.init(.{
        .minify = zmin.v2.MinifyConfig{
            .remove_whitespace = true,
            .remove_comments = true,
            .aggressive = false,
        },
    }));

    const custom_minified = try engine.processToString(allocator, input_json);
    defer allocator.free(custom_minified);
    std.debug.print("Custom Minified: {s}\n", .{custom_minified});

    // 3. Performance benchmark
    std.debug.print("\n3. Performance Benchmark:\n", .{});
    const benchmark_result = try zmin.benchmarkV2(allocator, input_json, 1000);
    benchmark_result.print();

    // 4. Multiple transformations
    std.debug.print("\n4. Multiple Transformations:\n", .{});
    var multi_engine = try zmin.v2.ZminEngine.init(allocator, .{});
    defer multi_engine.deinit();

    // Add minification transformation
    try multi_engine.addTransformation(zmin.v2.Transformation.init(.{
        .minify = zmin.v2.MinifyConfig{ .remove_whitespace = true },
    }).withPriority(1));

    // Add field filtering transformation (placeholder for now)
    try multi_engine.addTransformation(zmin.v2.Transformation.init(.{
        .filter_fields = zmin.v2.FilterConfig{
            .include = &[_][]const u8{ "name", "age", "email" },
            .exclude = null,
        },
    }).withPriority(2));

    const multi_result = try multi_engine.processToString(allocator, input_json);
    defer allocator.free(multi_result);
    std.debug.print("Multi-transformed: {s}\n", .{multi_result});

    // 5. Engine statistics
    std.debug.print("\n5. Engine Statistics:\n", .{});
    const stats = multi_engine.getStats();
    std.debug.print("Transformations executed: {}\n", .{stats.transformation_count});
    std.debug.print("Total execution time: {} ms\n", .{stats.total_execution_time});
    std.debug.print("Total transformation time: {} ms\n", .{stats.total_transformation_time});
    std.debug.print("Throughput: {d:.2} tokens/sec\n", .{stats.getThroughput()});
    std.debug.print("Memory efficiency: {d:.2} bytes/token\n", .{stats.getMemoryEfficiency()});

    std.debug.print("\n=== Demo Complete ===\n", .{});
}
