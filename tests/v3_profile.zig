const std = @import("std");
const TurboMinifierV3 = @import("../src/modes/turbo_minifier_v3.zig").TurboMinifierV3;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== TURBO V3 Detailed Profile ===\n\n", .{});

    // Test different patterns to identify bottlenecks
    const test_patterns = [_]struct { name: []const u8, json: []const u8 }{
        .{ .name = "Dense Structure", .json = generateDenseJson() },
        .{ .name = "String Heavy", .json = generateStringHeavyJson() },
        .{ .name = "Whitespace Heavy", .json = generateWhitespaceHeavyJson() },
        .{ .name = "Minimal Whitespace", .json = generateMinimalJson() },
        .{ .name = "Large Arrays", .json = generateLargeArrayJson() },
    };

    for (test_patterns) |pattern| {
        try stdout.print("Testing {s}...\n", .{pattern.name});

        var minifier = TurboMinifierV3.init(allocator);
        const output = try allocator.alloc(u8, pattern.json.len);
        defer allocator.free(output);

        // Warm up
        _ = try minifier.minify(pattern.json, output);

        // Benchmark
        var total_time: u64 = 0;
        const runs = 100;

        for (0..runs) |_| {
            var timer = try std.time.Timer.start();
            const len = try minifier.minify(pattern.json, output);
            const elapsed = timer.read();
            total_time += elapsed;
            _ = len;
        }

        const avg_time = total_time / runs;
        const throughput = (@as(f64, @floatFromInt(pattern.json.len)) / @as(f64, @floatFromInt(avg_time))) * 1000.0;

        try stdout.print("  Size: {} bytes\n", .{pattern.json.len});
        try stdout.print("  Throughput: {d:.2} MB/s\n", .{throughput});
        try stdout.print("  Time: {d:.2} µs\n\n", .{@as(f64, @floatFromInt(avg_time)) / 1000.0});
    }
}

fn generateDenseJson() []const u8 {
    return 
    \\{"a":1,"b":2,"c":3,"d":4,"e":5,"f":6,"g":7,"h":8,"i":9,"j":10,"k":11,"l":12,"m":13,"n":14,"o":15,"p":16,"q":17,"r":18,"s":19,"t":20,"u":21,"v":22,"w":23,"x":24,"y":25,"z":26}
    ;
}

fn generateStringHeavyJson() []const u8 {
    return 
    \\{"name":"This is a very long string with lots of content","description":"Another extremely long string that contains many words and characters","content":"Even more string content here with additional text","title":"Yet another string field","summary":"Final string with more text content"}
    ;
}

fn generateWhitespaceHeavyJson() []const u8 {
    return 
    \\{
    \\    "user": {
    \\        "profile": {
    \\            "name": "John Doe",
    \\            "settings": {
    \\                "theme": "dark",
    \\                "notifications": true
    \\            }
    \\        }
    \\    }
    \\}
    ;
}

fn generateMinimalJson() []const u8 {
    return 
    \\{"user":{"profile":{"name":"John","settings":{"theme":"dark","notifications":true}}}}
    ;
}

fn generateLargeArrayJson() []const u8 {
    return 
    \\{"data":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50]}
    ;
}
