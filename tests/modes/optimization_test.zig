const std = @import("std");
const TurboMinifierScalar = @import("turbo_minifier_scalar").TurboMinifierScalar;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== Optimization Investigation ===\n\n", .{});

    // Test 1: Different JSON patterns to find algorithm sensitivity
    try stdout.print("1. Testing different JSON patterns...\n", .{});

    // Test minimal whitespace
    {
        const test_json = try generateMinimalJson(allocator, 1024 * 1024);
        defer allocator.free(test_json);
        const result = try benchmarkMinifier(allocator, test_json);
        try stdout.print("  Minimal whitespace: {d:.2} MB/s (compression: {d:.1}%)\n", .{ result.throughput, (1.0 - @as(f64, @floatFromInt(result.output_size)) / @as(f64, @floatFromInt(test_json.len))) * 100.0 });
    }

    // Test heavy whitespace
    {
        const test_json = try generateWhitespaceJson(allocator, 1024 * 1024);
        defer allocator.free(test_json);
        const result = try benchmarkMinifier(allocator, test_json);
        try stdout.print("  Heavy whitespace: {d:.2} MB/s (compression: {d:.1}%)\n", .{ result.throughput, (1.0 - @as(f64, @floatFromInt(result.output_size)) / @as(f64, @floatFromInt(test_json.len))) * 100.0 });
    }

    // Test string heavy
    {
        const test_json = try generateStringJson(allocator, 1024 * 1024);
        defer allocator.free(test_json);
        const result = try benchmarkMinifier(allocator, test_json);
        try stdout.print("  String heavy: {d:.2} MB/s (compression: {d:.1}%)\n", .{ result.throughput, (1.0 - @as(f64, @floatFromInt(result.output_size)) / @as(f64, @floatFromInt(test_json.len))) * 100.0 });
    }

    // Test no strings
    {
        const test_json = try generateNoStringJson(allocator, 1024 * 1024);
        defer allocator.free(test_json);
        const result = try benchmarkMinifier(allocator, test_json);
        try stdout.print("  No strings: {d:.2} MB/s (compression: {d:.1}%)\n", .{ result.throughput, (1.0 - @as(f64, @floatFromInt(result.output_size)) / @as(f64, @floatFromInt(test_json.len))) * 100.0 });
    }

    // Test flat structure
    {
        const test_json = try generateFlatJson(allocator, 1024 * 1024);
        defer allocator.free(test_json);
        const result = try benchmarkMinifier(allocator, test_json);
        try stdout.print("  Flat structure: {d:.2} MB/s (compression: {d:.1}%)\n", .{ result.throughput, (1.0 - @as(f64, @floatFromInt(result.output_size)) / @as(f64, @floatFromInt(test_json.len))) * 100.0 });
    }

    // Test 2: Memory access patterns
    try stdout.print("\n2. Testing memory access patterns...\n", .{});

    // Generate large file for cache testing
    const large_json = try generateTestJson(allocator, 50 * 1024 * 1024);
    defer allocator.free(large_json);

    // Cold cache
    const cold_result = try benchmarkMinifier(allocator, large_json);
    try stdout.print("  Cold cache (50MB): {d:.2} MB/s\n", .{cold_result.throughput});

    // Warm cache
    _ = try benchmarkMinifier(allocator, large_json); // Warm up
    const warm_result = try benchmarkMinifier(allocator, large_json);
    try stdout.print("  Warm cache (50MB): {d:.2} MB/s ({d:.1}% improvement)\n", .{ warm_result.throughput, ((warm_result.throughput / cold_result.throughput) - 1.0) * 100.0 });

    // Test 3: Theoretical maximum - just copying without processing
    try stdout.print("\n3. Theoretical maximums...\n", .{});

    const copy_result = try benchmarkMemcpy(allocator, large_json);
    try stdout.print("  Pure memcpy: {d:.2} MB/s\n", .{copy_result});

    const scan_result = try benchmarkScan(allocator, large_json);
    try stdout.print("  Pure scan: {d:.2} MB/s\n", .{scan_result});

    try stdout.print("\n=== Analysis ===\n", .{});
    try stdout.print("Minifier efficiency: {d:.1}% of memcpy speed\n", .{(warm_result.throughput / copy_result) * 100.0});
}

const BenchResult = struct {
    throughput: f64,
    output_size: usize,
};

fn benchmarkMinifier(allocator: std.mem.Allocator, input: []const u8) !BenchResult {
    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);

    var minifier = TurboMinifierScalar.init(allocator);

    // Warm up
    _ = try minifier.minify(input, output);

    // Benchmark
    const runs = 3;
    var total_time: u64 = 0;
    var output_size: usize = 0;

    for (0..runs) |_| {
        var timer = try std.time.Timer.start();
        output_size = try minifier.minify(input, output);
        const elapsed = timer.read();
        total_time += elapsed;
    }

    const avg_time = total_time / runs;
    const seconds = @as(f64, @floatFromInt(avg_time)) / 1_000_000_000.0;
    const mb_per_sec = (@as(f64, @floatFromInt(input.len)) / (1024.0 * 1024.0)) / seconds;

    return BenchResult{
        .throughput = mb_per_sec,
        .output_size = output_size,
    };
}

fn benchmarkMemcpy(allocator: std.mem.Allocator, input: []const u8) !f64 {
    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);

    const runs = 3;
    var total_time: u64 = 0;

    for (0..runs) |_| {
        var timer = try std.time.Timer.start();
        @memcpy(output, input);
        const elapsed = timer.read();
        total_time += elapsed;
    }

    const avg_time = total_time / runs;
    const seconds = @as(f64, @floatFromInt(avg_time)) / 1_000_000_000.0;
    return (@as(f64, @floatFromInt(input.len)) / (1024.0 * 1024.0)) / seconds;
}

fn benchmarkScan(allocator: std.mem.Allocator, input: []const u8) !f64 {
    _ = allocator;

    const runs = 3;
    var total_time: u64 = 0;

    for (0..runs) |_| {
        var timer = try std.time.Timer.start();
        var count: usize = 0;
        for (input) |c| {
            if (c == '"') count += 1;
        }
        const elapsed = timer.read();
        total_time += elapsed;
        _ = &count;
    }

    const avg_time = total_time / runs;
    const seconds = @as(f64, @floatFromInt(avg_time)) / 1_000_000_000.0;
    return (@as(f64, @floatFromInt(input.len)) / (1024.0 * 1024.0)) / seconds;
}

// Pattern generators
fn generateMinimalJson(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    try result.appendSlice("{\"data\":[");

    while (result.items.len < size - 20) {
        try result.appendSlice("{\"k\":1},");
    }

    try result.appendSlice("{\"k\":1}]}");
    return result.toOwnedSlice();
}

fn generateWhitespaceJson(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    try result.appendSlice("{\n    \"data\": [\n");

    while (result.items.len < size - 100) {
        try result.appendSlice("        {\n            \"key\": 123\n        },\n");
    }

    try result.appendSlice("    ]\n}\n");
    return result.toOwnedSlice();
}

fn generateStringJson(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    try result.appendSlice("{\"strings\":[");

    while (result.items.len < size - 100) {
        try result.appendSlice("\"This is a long string with many words and characters\",");
    }

    try result.appendSlice("\"end\"]}");
    return result.toOwnedSlice();
}

fn generateNoStringJson(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    try result.appendSlice("{");

    var i: usize = 0;
    while (result.items.len < size - 50) : (i += 1) {
        const kv = try std.fmt.allocPrint(allocator, "a{d}:{d},", .{ i, i });
        defer allocator.free(kv);
        try result.appendSlice(kv);
    }

    try result.appendSlice("z:0}");
    return result.toOwnedSlice();
}

fn generateFlatJson(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    try result.appendSlice("{");

    var i: usize = 0;
    while (result.items.len < size - 100) : (i += 1) {
        const kv = try std.fmt.allocPrint(allocator, "\"field{d}\":\"value{d}\",", .{ i, i });
        defer allocator.free(kv);
        try result.appendSlice(kv);
    }

    try result.appendSlice("\"end\":\"done\"}");
    return result.toOwnedSlice();
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
