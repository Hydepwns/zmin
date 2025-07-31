// Benchmark to test SIMD whitespace detection performance improvement
const std = @import("std");
const modes = @import("modes");
const MinifierInterface = @import("minifier_interface").MinifierInterface;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\nTURBO Mode SIMD Performance Benchmark\n", .{});
    try stdout.print("=========================================\n\n", .{});

    // Test with different file sizes and whitespace patterns
    const test_cases = [_]struct { 
        name: []const u8, 
        size: usize,
        whitespace_density: f32,
    }{
        .{ .name = "Low whitespace (100KB)", .size = 100 * 1024, .whitespace_density = 0.1 },
        .{ .name = "Normal whitespace (100KB)", .size = 100 * 1024, .whitespace_density = 0.3 },
        .{ .name = "High whitespace (100KB)", .size = 100 * 1024, .whitespace_density = 0.5 },
        .{ .name = "Low whitespace (1MB)", .size = 1024 * 1024, .whitespace_density = 0.1 },
        .{ .name = "Normal whitespace (1MB)", .size = 1024 * 1024, .whitespace_density = 0.3 },
        .{ .name = "High whitespace (1MB)", .size = 1024 * 1024, .whitespace_density = 0.5 },
    };

    try stdout.print("Comparing TURBO mode (with SIMD) vs SPORT mode (no SIMD):\n\n", .{});

    for (test_cases) |test_case| {
        try stdout.print("Testing {s}:\n", .{test_case.name});

        // Generate test data with specific whitespace density
        const input = try generateTestJsonWithWhitespace(allocator, test_case.size, test_case.whitespace_density);
        defer allocator.free(input);

        // Test SPORT mode (no SIMD)
        var sport_time: u64 = 0;
        {
            var timer = try std.time.Timer.start();
            const result = try MinifierInterface.minifyString(allocator, .sport, input);
            sport_time = timer.read();
            allocator.free(result);
        }

        // Test TURBO mode (with SIMD)
        var turbo_time: u64 = 0;
        {
            var timer = try std.time.Timer.start();
            const result = try MinifierInterface.minifyString(allocator, .turbo, input);
            turbo_time = timer.read();
            allocator.free(result);
        }

        const sport_ms = @as(f64, @floatFromInt(sport_time)) / 1_000_000.0;
        const turbo_ms = @as(f64, @floatFromInt(turbo_time)) / 1_000_000.0;
        const speedup = sport_ms / turbo_ms;

        const sport_throughput = (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(sport_time))) * 1000.0;
        const turbo_throughput = (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(turbo_time))) * 1000.0;

        try stdout.print("  SPORT mode: {d:.2}ms ({d:.2} MB/s)\n", .{ sport_ms, sport_throughput });
        try stdout.print("  TURBO mode: {d:.2}ms ({d:.2} MB/s)\n", .{ turbo_ms, turbo_throughput });
        try stdout.print("  Speedup: {d:.2}x\n\n", .{speedup});
    }
}

fn generateTestJsonWithWhitespace(allocator: std.mem.Allocator, target_size: usize, whitespace_density: f32) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = rng.random();

    try result.appendSlice("{\n");
    try result.appendSlice("  \"data\": [\n");

    var current_size: usize = result.items.len;
    var id: usize = 0;

    while (current_size < target_size - 100) {
        if (id > 0) {
            try result.appendSlice(",\n");
        }

        // Add random whitespace based on density
        const whitespace_count = @as(usize, @intFromFloat(@as(f32, @floatFromInt(random.int(u8))) * whitespace_density));
        for (0..whitespace_count) |_| {
            const ws_type = random.int(u8) % 3;
            switch (ws_type) {
                0 => try result.append(' '),
                1 => try result.append('\t'),
                2 => try result.append('\n'),
                else => unreachable,
            }
        }

        const item = try std.fmt.allocPrint(allocator,
            \\    {{
            \\      "id": {d},
            \\      "value": {d}
            \\    }}
        , .{ id, random.int(u32) });
        defer allocator.free(item);

        try result.appendSlice(item);
        current_size = result.items.len;
        id += 1;
    }

    try result.appendSlice("\n  ]\n}\n");
    return result.toOwnedSlice();
}