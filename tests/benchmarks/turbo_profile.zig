// Profile TURBO mode to identify performance bottlenecks

const std = @import("std");
const TurboMinifier = @import("turbo_minifier").TurboMinifier;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    try stdout.print("=== TURBO Mode Performance Analysis ===\n\n", .{});

    // Test with different patterns to identify bottlenecks
    const test_patterns = [_]struct { name: []const u8, generator: *const fn (allocator: std.mem.Allocator, size: usize) anyerror![]u8 }{
        .{ .name = "No Strings (pure structure)", .generator = generateNoStrings },
        .{ .name = "All Strings", .generator = generateAllStrings },
        .{ .name = "Mixed (50/50)", .generator = generateMixed },
        .{ .name = "Heavy Whitespace", .generator = generateHeavyWhitespace },
        .{ .name = "Minimal Whitespace", .generator = generateMinimalWhitespace },
        .{ .name = "Aligned Data", .generator = generateAligned },
    };

    const test_size = 1024 * 1024; // 1MB

    for (test_patterns) |pattern| {
        try stdout.print("Testing pattern: {s}\n", .{pattern.name});

        const input = try pattern.generator(allocator, test_size);
        defer allocator.free(input);

        var minifier = TurboMinifier.init(allocator);

        // Warm up
        const output = try allocator.alloc(u8, input.len);
        defer allocator.free(output);
        _ = try minifier.minify(input, output);

        // Measure
        const runs = 10;
        var total_time: u64 = 0;

        for (0..runs) |_| {
            var timer = try std.time.Timer.start();
            const len = try minifier.minify(input, output);
            const elapsed = timer.read();
            total_time += elapsed;
            _ = len;
        }

        const avg_time = total_time / runs;
        const throughput_mbps = (@as(f64, @floatFromInt(test_size)) / @as(f64, @floatFromInt(avg_time))) * 1000.0;

        try stdout.print("  Throughput: {d:.2} MB/s\n", .{throughput_mbps});
        try stdout.print("  Time per MB: {d:.2} ms\n\n", .{@as(f64, @floatFromInt(avg_time)) / 1_000_000.0});
    }

    // Detailed timing breakdown
    try stdout.print("Analyzing processing phases...\n\n", .{});

    const mixed_input = try generateMixed(allocator, test_size);
    defer allocator.free(mixed_input);

    // Count different character types
    var quotes: usize = 0;
    var whitespace: usize = 0;
    var other: usize = 0;

    for (mixed_input) |c| {
        if (c == '"') quotes += 1 else if (c == ' ' or c == '\t' or c == '\n' or c == '\r') whitespace += 1 else other += 1;
    }

    try stdout.print("Input composition:\n", .{});
    try stdout.print("  Quotes: {} ({d:.1}%)\n", .{ quotes, @as(f64, @floatFromInt(quotes)) / @as(f64, @floatFromInt(test_size)) * 100 });
    try stdout.print("  Whitespace: {} ({d:.1}%)\n", .{ whitespace, @as(f64, @floatFromInt(whitespace)) / @as(f64, @floatFromInt(test_size)) * 100 });
    try stdout.print("  Other: {} ({d:.1}%)\n", .{ other, @as(f64, @floatFromInt(other)) / @as(f64, @floatFromInt(test_size)) * 100 });
}

fn generateNoStrings(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    // Generate JSON with numbers and booleans only
    try result.appendSlice("{\n");

    var current = result.items.len;
    var id: usize = 0;

    while (current < size - 100) {
        if (id > 0) try result.appendSlice(",\n");

        const item = try std.fmt.allocPrint(allocator,
            \\  "item{d}": {{
            \\    "id": {d},
            \\    "value": {d},
            \\    "active": {s},
            \\    "score": {d}.{d}
            \\  }}
        , .{ id, id, id * 10, if (id % 2 == 0) "true" else "false", id % 100, id % 10 });
        defer allocator.free(item);

        try result.appendSlice(item);
        current = result.items.len;
        id += 1;
    }

    try result.appendSlice("\n}\n");
    return result.toOwnedSlice();
}

fn generateAllStrings(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    try result.appendSlice("{\n");

    var current = result.items.len;
    var id: usize = 0;

    while (current < size - 100) {
        if (id > 0) try result.appendSlice(",\n");

        const item = try std.fmt.allocPrint(allocator,
            \\  "field{d}": "This is a string value with some content in it {d}"
        , .{ id, id });
        defer allocator.free(item);

        try result.appendSlice(item);
        current = result.items.len;
        id += 1;
    }

    try result.appendSlice("\n}\n");
    return result.toOwnedSlice();
}

fn generateMixed(allocator: std.mem.Allocator, size: usize) ![]u8 {
    // Use the same generator from before
    var result = std.ArrayList(u8).init(allocator);

    try result.appendSlice("{\n  \"users\": [\n");

    var current = result.items.len;
    var id: usize = 0;

    while (current < size - 100) {
        if (id > 0) try result.appendSlice(",\n");

        const user = try std.fmt.allocPrint(allocator,
            \\    {{
            \\      "id": {d},
            \\      "name": "User {d}",
            \\      "email": "user{d}@example.com",
            \\      "active": {s}
            \\    }}
        , .{ id, id, id, if (id % 2 == 0) "true" else "false" });
        defer allocator.free(user);

        try result.appendSlice(user);
        current = result.items.len;
        id += 1;
    }

    try result.appendSlice("\n  ]\n}\n");
    return result.toOwnedSlice();
}

fn generateHeavyWhitespace(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    try result.appendSlice("{\n");

    var current = result.items.len;
    var id: usize = 0;

    while (current < size - 200) {
        if (id > 0) try result.appendSlice("  ,  \n\n");

        const item = try std.fmt.allocPrint(allocator,
            \\    "item{d}"    :    {{
            \\        "value"    :    {d}    ,
            \\        "active"    :    {s}
            \\    }}
        , .{ id, id, if (id % 2 == 0) "true" else "false" });
        defer allocator.free(item);

        try result.appendSlice(item);
        current = result.items.len;
        id += 1;
    }

    try result.appendSlice("\n\n}\n\n");
    return result.toOwnedSlice();
}

fn generateMinimalWhitespace(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    try result.appendSlice("{");

    var current = result.items.len;
    var id: usize = 0;

    while (current < size - 100) {
        if (id > 0) try result.appendSlice(",");

        const item = try std.fmt.allocPrint(allocator,
            \\"item{d}":{{"value":{d},"active":{s}}}
        , .{ id, id, if (id % 2 == 0) "true" else "false" });
        defer allocator.free(item);

        try result.appendSlice(item);
        current = result.items.len;
        id += 1;
    }

    try result.appendSlice("}");
    return result.toOwnedSlice();
}

fn generateAligned(allocator: std.mem.Allocator, size: usize) ![]u8 {
    // Generate data that's aligned to 32-byte boundaries
    const alignment = 32;
    const buffer = try allocator.alignedAlloc(u8, alignment, size + alignment);
    defer allocator.free(buffer);

    var result = std.ArrayList(u8).init(allocator);
    result.items = buffer[0..0];
    result.capacity = buffer.len;

    try result.appendSlice("{\"data\":[");

    // Pad to alignment
    while (result.items.len % alignment != 0) {
        try result.append(' ');
    }

    var current = result.items.len;
    var id: usize = 0;

    while (current < size - 100) {
        if (id > 0) {
            try result.appendSlice(",");
            // Pad to maintain alignment
            while (result.items.len % alignment != 0) {
                try result.append(' ');
            }
        }

        const item = try std.fmt.allocPrint(allocator, "{d}", .{id});
        defer allocator.free(item);

        try result.appendSlice(item);
        current = result.items.len;
        id += 1;
    }

    try result.appendSlice("]}");
    const final_len = result.items.len;

    // Return a new allocation with just the data
    const final_result = try allocator.alloc(u8, final_len);
    @memcpy(final_result, result.items[0..final_len]);
    return final_result;
}
