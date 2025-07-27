const std = @import("std");
const TurboMinifierStreaming = @import("turbo_minifier_streaming").TurboMinifierStreaming;
const TurboMinifierMegaBulk = @import("turbo_minifier_streaming").TurboMinifierMegaBulk;
const TurboMinifierScalar = @import("turbo_minifier_scalar").TurboMinifierScalar;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== TURBO Streaming Bulk Operations Test ===\n\n", .{});

    // Test with different sizes to find scaling behavior
    const sizes = [_]usize{ 100 * 1024, 1024 * 1024, 10 * 1024 * 1024 };
    const size_names = [_][]const u8{ "100KB", "1MB", "10MB" };

    for (sizes, size_names) |size, size_name| {
        try stdout.print("Testing {s} ({} bytes)...\n", .{ size_name, size });

        const test_json = try generateTestJson(allocator, size);
        defer allocator.free(test_json);

        // Test Scalar baseline
        try stdout.print("  Scalar:    ", .{});
        const scalar_result = try testMinifier(allocator, test_json, testScalar);
        try stdout.print("{d:.2} MB/s\n", .{scalar_result.throughput});

        // Test Streaming
        try stdout.print("  Streaming: ", .{});
        const streaming_result = try testMinifier(allocator, test_json, testStreaming);
        try stdout.print("{d:.2} MB/s ({d:.2}x)\n", .{ streaming_result.throughput, streaming_result.throughput / scalar_result.throughput });

        // Test MegaBulk
        try stdout.print("  MegaBulk:  ", .{});
        const megabulk_result = try testMinifier(allocator, test_json, testMegaBulk);
        try stdout.print("{d:.2} MB/s ({d:.2}x)\n", .{ megabulk_result.throughput, megabulk_result.throughput / scalar_result.throughput });

        const best = @max(scalar_result.throughput, @max(streaming_result.throughput, megabulk_result.throughput));
        if (best > 500) {
            try stdout.print("  🚀 BREAKTHROUGH: {d:.2} MB/s!\n", .{best});
        } else if (best > 300) {
            try stdout.print("  ⚡ Good progress: {d:.2} MB/s\n", .{best});
        }
        try stdout.print("\n", .{});
    }
}

const TestResult = struct {
    throughput: f64,
};

fn testMinifier(allocator: std.mem.Allocator, input: []const u8, minify_fn: anytype) !TestResult {
    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);

    // Warm up
    _ = try minify_fn(allocator, input, output);

    // Benchmark
    var total_time: u64 = 0;
    const runs: usize = if (input.len > 1024 * 1024) 3 else 10;

    for (0..runs) |_| {
        var timer = try std.time.Timer.start();
        const len = try minify_fn(allocator, input, output);
        const elapsed = timer.read();
        total_time += elapsed;
        _ = len;
    }

    const avg_time = total_time / runs;
    const seconds = @as(f64, @floatFromInt(avg_time)) / 1_000_000_000.0;
    const mb_per_sec = (@as(f64, @floatFromInt(input.len)) / (1024.0 * 1024.0)) / seconds;

    return TestResult{
        .throughput = mb_per_sec,
    };
}

fn testScalar(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierScalar.init(allocator);
    return minifier.minify(input, output);
}

fn testStreaming(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierStreaming.init(allocator);
    return minifier.minify(input, output);
}

fn testMegaBulk(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierMegaBulk.init(allocator);
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
