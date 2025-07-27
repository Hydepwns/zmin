const std = @import("std");
const TurboMinifierScalar = @import("turbo_minifier_scalar").TurboMinifierScalar;
const TurboMinifierDirect = @import("turbo_minifier_mmap").TurboMinifierDirect;
const TurboMinifierParallel = @import("turbo_minifier_parallel").TurboMinifierParallel;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== TURBO Final Performance Test ===\n\n", .{});

    // Test with increasing sizes
    const sizes = [_]usize{
        100 * 1024, // 100KB
        1024 * 1024, // 1MB
        10 * 1024 * 1024, // 10MB
        50 * 1024 * 1024, // 50MB
    };
    const size_names = [_][]const u8{ "100KB", "1MB", "10MB", "50MB" };

    for (sizes, size_names) |size, size_name| {
        try stdout.print("{s} Test:\n", .{size_name});

        const test_json = try generateTestJson(allocator, size);
        defer allocator.free(test_json);

        // Test scalar baseline
        const scalar_tp = try benchmarkMinifier(allocator, test_json, testScalar);
        try stdout.print("  Scalar:   {d:.2} MB/s (baseline)\n", .{scalar_tp});

        // Test direct (minimal overhead)
        const direct_tp = try benchmarkMinifier(allocator, test_json, testDirect);
        try stdout.print("  Direct:   {d:.2} MB/s ({d:.1}x)\n", .{ direct_tp, direct_tp / scalar_tp });

        // Test parallel (multi-threaded)
        if (size >= 1024 * 1024) { // Only for larger files
            const parallel_tp = try benchmarkMinifier(allocator, test_json, testParallel);
            try stdout.print("  Parallel: {d:.2} MB/s ({d:.1}x) - {d} threads\n", .{ parallel_tp, parallel_tp / scalar_tp, std.Thread.getCpuCount() catch 1 });

            if (parallel_tp > 800) {
                try stdout.print("  🚀 BREAKTHROUGH: {d:.2} MB/s achieved!\n", .{parallel_tp});
                if (parallel_tp > 2000) {
                    try stdout.print("  🎯 TARGET REACHED: 2+ GB/s!\n", .{});
                }
            }
        }

        try stdout.print("\n", .{});
    }

    // Summary
    try stdout.print("=== Analysis ===\n", .{});
    try stdout.print("CPU cores available: {}\n", .{std.Thread.getCpuCount() catch 1});

    // Test pure memory bandwidth
    const large_data = try allocator.alloc(u8, 50 * 1024 * 1024);
    defer allocator.free(large_data);

    var timer = try std.time.Timer.start();
    @memset(large_data, 0);
    const memset_time = timer.read();
    const memset_throughput = (50.0 * 1024.0) / (@as(f64, @floatFromInt(memset_time)) / 1_000_000.0);

    try stdout.print("Memory bandwidth (memset): {d:.0} MB/s\n", .{memset_throughput});
}

fn benchmarkMinifier(allocator: std.mem.Allocator, input: []const u8, minify_fn: anytype) !f64 {
    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);

    // Warm up
    _ = try minify_fn(allocator, input, output);

    const runs: usize = if (input.len > 10 * 1024 * 1024) 3 else if (input.len > 1024 * 1024) 5 else 10;
    var total_time: u64 = 0;

    for (0..runs) |_| {
        var timer = try std.time.Timer.start();
        _ = try minify_fn(allocator, input, output);
        const elapsed = timer.read();
        total_time += elapsed;
    }

    const avg_time = total_time / runs;
    const seconds = @as(f64, @floatFromInt(avg_time)) / 1_000_000_000.0;
    return (@as(f64, @floatFromInt(input.len)) / (1024.0 * 1024.0)) / seconds;
}

fn testScalar(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierScalar.init(allocator);
    return minifier.minify(input, output);
}

fn testDirect(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierDirect.init(allocator);
    return minifier.minify(input, output);
}

fn testParallel(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierParallel.init(allocator);
    return minifier.minify(input, output);
}

fn generateTestJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    try result.appendSlice("{\n  \"users\": [\n");

    var current_size: usize = result.items.len;
    var id: usize = 0;

    while (current_size < target_size - 100) {
        if (id > 0) {
            try result.appendSlice(",\n");
        }

        const indent = if (id % 3 == 0) "    " else if (id % 3 == 1) "\t\t" else "  ";

        const user = try std.fmt.allocPrint(allocator,
            \\{s}{{
            \\{s}  "id": {d},
            \\{s}  "name": "User {d}",
            \\{s}  "email": "user{d}@example.com",
            \\{s}  "active": {s},
            \\{s}  "tags": ["tag1", "tag2", "tag3"],
            \\{s}  "score": {d}.{d}
            \\{s}}}
        , .{
            indent,  indent, id,
            indent,  id,     indent,
            id,      indent, if (id % 2 == 0) "true" else "false",
            indent,  indent, id % 100,
            id % 10, indent,
        });
        defer allocator.free(user);

        try result.appendSlice(user);
        current_size = result.items.len;
        id += 1;
    }

    try result.appendSlice("\n  ]\n}\n");
    return result.toOwnedSlice();
}
