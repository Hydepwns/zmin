const std = @import("std");
const TurboMinifierV3 = @import("turbo_minifier_v3").TurboMinifierV3;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== Debug Benchmark Data ===\n\n", .{});

    // Generate same data as benchmark for 1MB test
    const test_json = try generateTestJson(allocator, 1024 * 1024);
    defer allocator.free(test_json);

    try stdout.print("Generated JSON size: {} bytes\n", .{test_json.len});
    try stdout.print("First 200 chars: {s}\n", .{test_json[0..@min(200, test_json.len)]});
    try stdout.print("Last 200 chars: {s}\n\n", .{test_json[test_json.len - @min(200, test_json.len) ..]});

    // Analyze content
    var quotes: usize = 0;
    var whitespace: usize = 0;
    var other: usize = 0;

    for (test_json) |c| {
        if (c == '"') {
            quotes += 1;
        } else if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            whitespace += 1;
        } else {
            other += 1;
        }
    }

    try stdout.print("Content analysis:\n", .{});
    try stdout.print("  Quotes: {} ({d:.1}%)\n", .{ quotes, (@as(f64, @floatFromInt(quotes)) / @as(f64, @floatFromInt(test_json.len))) * 100.0 });
    try stdout.print("  Whitespace: {} ({d:.1}%)\n", .{ whitespace, (@as(f64, @floatFromInt(whitespace)) / @as(f64, @floatFromInt(test_json.len))) * 100.0 });
    try stdout.print("  Other: {} ({d:.1}%)\n\n", .{ other, (@as(f64, @floatFromInt(other)) / @as(f64, @floatFromInt(test_json.len))) * 100.0 });

    // Test V3 performance on this exact data
    var minifier = TurboMinifierV3.init(allocator);
    const output = try allocator.alloc(u8, test_json.len);
    defer allocator.free(output);

    // Warm up
    _ = try minifier.minify(test_json, output);

    // Benchmark exactly like the benchmark does
    var total_time: u64 = 0;
    const runs = 3; // Same as benchmark for 1MB

    for (0..runs) |_| {
        var timer = try std.time.Timer.start();
        const len = try minifier.minify(test_json, output);
        const elapsed = timer.read();
        total_time += elapsed;
        _ = len;
    }

    const avg_time = total_time / runs;
    const seconds = @as(f64, @floatFromInt(avg_time)) / 1_000_000_000.0;
    const mb_per_sec = (@as(f64, @floatFromInt(test_json.len)) / (1024.0 * 1024.0)) / seconds;

    try stdout.print("V3 Performance on benchmark data:\n", .{});
    try stdout.print("  Throughput: {d:.2} MB/s\n", .{mb_per_sec});
    try stdout.print("  Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(avg_time)) / 1_000_000.0});
}

// Exact copy of benchmark generator
fn generateTestJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    try result.appendSlice("{\n  \"users\": [\n");

    var current_size: usize = result.items.len;
    var id: usize = 0;

    while (current_size < target_size - 100) {
        if (id > 0) {
            try result.appendSlice(",\n");
        }

        // Mix of whitespace patterns
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
