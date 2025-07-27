const std = @import("std");
const TurboMinifierV3 = @import("turbo_minifier_v3").TurboMinifierV3;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== TURBO V3 Scaling Analysis ===\n\n", .{});

    // Test with increasingly large files to find memory bandwidth ceiling
    const sizes = [_]usize{
        1024, // 1KB
        10 * 1024, // 10KB
        100 * 1024, // 100KB
        1024 * 1024, // 1MB
        10 * 1024 * 1024, // 10MB
        50 * 1024 * 1024, // 50MB - test memory bandwidth
    };
    const size_names = [_][]const u8{ "1KB", "10KB", "100KB", "1MB", "10MB", "50MB" };

    for (sizes, size_names) |size, size_name| {
        try stdout.print("Testing {s} ({} bytes)...\n", .{ size_name, size });

        // Generate test data with realistic JSON patterns
        const test_json = try generateRealisticJson(allocator, size);
        defer allocator.free(test_json);

        var minifier = TurboMinifierV3.init(allocator);
        const output = try allocator.alloc(u8, test_json.len);
        defer allocator.free(output);

        // Warm up
        _ = try minifier.minify(test_json, output);

        // Benchmark with fewer runs for large sizes
        const runs: usize = if (size > 10 * 1024 * 1024) 3 else 10;
        var total_time: u64 = 0;

        for (0..runs) |_| {
            var timer = try std.time.Timer.start();
            const len = try minifier.minify(test_json, output);
            const elapsed = timer.read();
            total_time += elapsed;
            _ = len;
        }

        const avg_time = total_time / runs;
        const seconds = @as(f64, @floatFromInt(avg_time)) / 1_000_000_000.0;
        const mb_per_sec = (@as(f64, @floatFromInt(size)) / (1024.0 * 1024.0)) / seconds;

        try stdout.print("  Throughput: {d:.2} MB/s\n", .{mb_per_sec});
        try stdout.print("  Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(avg_time)) / 1_000_000.0});

        // Calculate theoretical memory bandwidth usage
        const bytes_read = size;
        const bytes_written = size / 2; // Assume ~50% compression
        const total_bandwidth = bytes_read + bytes_written;
        const bandwidth_gb_s = (@as(f64, @floatFromInt(total_bandwidth)) / (1024.0 * 1024.0 * 1024.0)) / seconds;

        try stdout.print("  Memory bandwidth: {d:.2} GB/s\n\n", .{bandwidth_gb_s});

        // Check if we're hitting memory bandwidth ceiling
        if (size > 1024 * 1024 and mb_per_sec < 2000) {
            try stdout.print("  ⚠️  May be hitting memory bandwidth ceiling\n\n", .{});
        }
    }
}

fn generateRealisticJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    try result.appendSlice("{\n  \"users\": [\n");

    var current_size: usize = result.items.len;
    var id: usize = 0;

    while (current_size < target_size - 500) { // Leave room for closing
        if (id > 0) {
            try result.appendSlice(",\n");
        }

        // Create realistic user objects with mixed content
        const user = try std.fmt.allocPrint(allocator,
            \\    {{
            \\      "id": {d},
            \\      "name": "User {d} with a longer name",
            \\      "email": "user{d}@company-domain.com",
            \\      "active": {s},
            \\      "metadata": {{
            \\        "lastLogin": "2024-01-{d:0>2}T10:30:00Z",
            \\        "permissions": ["read", "write", "admin"],
            \\        "score": {d}.{d}
            \\      }}
            \\    }}
        , .{ id, id, id, if (id % 2 == 0) "true" else "false", (id % 28) + 1, id % 1000, id % 100 });
        defer allocator.free(user);

        try result.appendSlice(user);
        current_size = result.items.len;
        id += 1;
    }

    try result.appendSlice("\n  ],\n");
    try result.appendSlice("  \"metadata\": {\n");
    try result.appendSlice("    \"totalUsers\": ");
    const total_str = try std.fmt.allocPrint(allocator, "{d}", .{id});
    defer allocator.free(total_str);
    try result.appendSlice(total_str);
    try result.appendSlice(",\n    \"generatedAt\": \"2024-01-15T12:00:00Z\"\n");
    try result.appendSlice("  }\n}\n");

    return result.toOwnedSlice();
}
