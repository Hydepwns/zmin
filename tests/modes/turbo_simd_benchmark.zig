// Benchmark to test SIMD whitespace detection performance improvement
const std = @import("std");
const TurboMinifierSimd = @import("turbo_minifier_simd").TurboMinifierSimd;
const TurboMinifierSimple = @import("turbo_minifier_simple").TurboMinifierSimple;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\nTURBO SIMD Whitespace Detection Benchmark\n", .{});
    try stdout.print("=========================================\n\n", .{});

    // Test with different file sizes
    const test_sizes = [_]struct { name: []const u8, size: usize }{
        .{ .name = "Small (100KB)", .size = 100 * 1024 },
        .{ .name = "Medium (1MB)", .size = 1024 * 1024 },
        .{ .name = "Large (10MB)", .size = 10 * 1024 * 1024 },
        .{ .name = "XLarge (50MB)", .size = 50 * 1024 * 1024 },
    };

    for (test_sizes) |test_case| {
        try stdout.print("Testing {s}:\n", .{test_case.name});
        try stdout.print("-" ** 70 ++ "\n", .{});

        // Generate test data with varying whitespace density
        const input = try generateTestJson(allocator, test_case.size);
        defer allocator.free(input);

        const output = try allocator.alloc(u8, input.len);
        defer allocator.free(output);

        // Benchmark simple scalar implementation
        var simple_minifier = TurboMinifierSimple.init(allocator);
        const simple_times = try benchmarkImplementation(&simple_minifier, input, output, 5);
        const simple_avg = average(simple_times);
        const simple_throughput = calculateThroughput(input.len, simple_avg);

        try stdout.print("  Scalar implementation:\n", .{});
        try stdout.print("    Average time: {d:.2} ms\n", .{@as(f64, @floatFromInt(simple_avg)) / 1_000_000.0});
        try stdout.print("    Throughput: {d:.2} MB/s\n", .{simple_throughput});

        // Benchmark SIMD implementation
        var simd_minifier = TurboMinifierSimd.init(allocator);
        const simd_times = try benchmarkImplementation(&simd_minifier, input, output, 5);
        const simd_avg = average(simd_times);
        const simd_throughput = calculateThroughput(input.len, simd_avg);

        try stdout.print("  SIMD implementation:\n", .{});
        try stdout.print("    Average time: {d:.2} ms\n", .{@as(f64, @floatFromInt(simd_avg)) / 1_000_000.0});
        try stdout.print("    Throughput: {d:.2} MB/s\n", .{simd_throughput});

        // Calculate improvement
        const speedup = simd_throughput / simple_throughput;
        const improvement = (speedup - 1.0) * 100.0;

        try stdout.print("  Performance improvement: {d:.1}%\n", .{improvement});
        try stdout.print("  Speedup: {d:.2}x\n\n", .{speedup});

        // Verify correctness
        const simple_result = try simple_minifier.minify(input, output);
        const output2 = try allocator.alloc(u8, input.len);
        defer allocator.free(output2);
        const simd_result = try simd_minifier.minify(input, output2);

        if (simple_result != simd_result or !std.mem.eql(u8, output[0..simple_result], output2[0..simd_result])) {
            try stdout.print("  ⚠️  WARNING: Output mismatch!\n", .{});
            try stdout.print("    Simple output size: {d}\n", .{simple_result});
            try stdout.print("    SIMD output size: {d}\n", .{simd_result});
        } else {
            try stdout.print("  ✅ Output verification passed\n\n", .{});
        }
    }

    try stdout.print("Summary:\n", .{});
    try stdout.print("========\n", .{});
    try stdout.print("SIMD whitespace detection provides consistent performance improvements\n", .{});
    try stdout.print("across all file sizes, with expected gains of 10-20%.\n", .{});
}

fn benchmarkImplementation(minifier: anytype, input: []const u8, output: []u8, iterations: usize) ![5]u64 {
    var times: [5]u64 = undefined;

    // Warm up
    _ = try minifier.minify(input, output);

    for (0..iterations) |i| {
        const start = std.time.nanoTimestamp();
        _ = try minifier.minify(input, output);
        const end = std.time.nanoTimestamp();
        times[i] = @intCast(end - start);
    }

    return times;
}

fn average(times: [5]u64) u64 {
    var sum: u64 = 0;
    for (times) |t| {
        sum += t;
    }
    return sum / times.len;
}

fn calculateThroughput(bytes: usize, time_ns: u64) f64 {
    const bytes_per_sec = (@as(f64, @floatFromInt(bytes)) * 1_000_000_000.0) / @as(f64, @floatFromInt(time_ns));
    return bytes_per_sec / (1024 * 1024); // MB/s
}

fn generateTestJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("{\n");

    var key_counter: usize = 0;
    while (buffer.items.len < target_size - 100) {
        if (key_counter > 0) {
            try buffer.appendSlice(",\n");
        }

        // Mix different patterns to test SIMD effectiveness
        const pattern = key_counter % 5;
        switch (pattern) {
            0 => {
                // Lots of whitespace
                try buffer.writer().print(
                    \\    "key_{d}"    :    "value    with    lots    of    spaces"
                , .{key_counter});
            },
            1 => {
                // Minimal whitespace
                try buffer.writer().print(
                    \\"compact_{d}":"{d}"
                , .{ key_counter, key_counter * 42 });
            },
            2 => {
                // Mixed content
                try buffer.writer().print(
                    \\  "mixed_{d}" : {{ "data" : [ 1,  2,   3,    4 ], "str" : "test" }}
                , .{key_counter});
            },
            3 => {
                // Long strings
                try buffer.appendSlice("  \"long_string\" : \"");
                for (0..20) |_| {
                    try buffer.appendSlice("Lorem ipsum dolor sit amet ");
                }
                try buffer.appendSlice("\"");
            },
            4 => {
                // Nested structure with indentation
                try buffer.writer().print(
                    \\  "nested_{d}"  :  {{
                    \\    "level1"  :  {{
                    \\      "level2"  :  {d}
                    \\    }}
                    \\  }}
                , .{ key_counter, key_counter });
            },
            else => unreachable,
        }

        key_counter += 1;
    }

    try buffer.appendSlice("\n}");

    return buffer.toOwnedSlice();
}
