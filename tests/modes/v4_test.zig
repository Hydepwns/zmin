const std = @import("std");
const TurboMinifierV4 = @import("turbo_minifier_v4").TurboMinifierV4;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== TURBO V4 Maximum Bandwidth Test ===\n\n", .{});
    
    // Generate benchmark data for 1MB test
    const test_json = try generateTestJson(allocator, 1024 * 1024);
    defer allocator.free(test_json);
    
    try stdout.print("Testing V4 on {} bytes...\n", .{test_json.len});
    
    var minifier = TurboMinifierV4.init(allocator);
    const output = try allocator.alloc(u8, test_json.len);
    defer allocator.free(output);
    
    // Correctness test first
    const len = try minifier.minify(test_json, output);
    try stdout.print("Output length: {} bytes\n", .{len});
    
    // Performance test
    var total_time: u64 = 0;
    const runs = 10;
    
    for (0..runs) |_| {
        var timer = try std.time.Timer.start();
        const result_len = try minifier.minify(test_json, output);
        const elapsed = timer.read();
        total_time += elapsed;
        _ = result_len;
    }
    
    const avg_time = total_time / runs;
    const seconds = @as(f64, @floatFromInt(avg_time)) / 1_000_000_000.0;
    const mb_per_sec = (@as(f64, @floatFromInt(test_json.len)) / (1024.0 * 1024.0)) / seconds;
    
    try stdout.print("V4 Performance:\n", .{});
    try stdout.print("  Throughput: {d:.2} MB/s\n", .{mb_per_sec});
    try stdout.print("  Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(avg_time)) / 1_000_000.0});
    
    // Memory bandwidth calculation
    const bytes_read = test_json.len;
    const bytes_written = len;
    const total_bandwidth = bytes_read + bytes_written;
    const bandwidth_gb_s = (@as(f64, @floatFromInt(total_bandwidth)) / (1024.0 * 1024.0 * 1024.0)) / seconds;
    
    try stdout.print("  Memory bandwidth: {d:.2} GB/s\n", .{bandwidth_gb_s});
    
    if (mb_per_sec > 500) {
        try stdout.print("  🚀 BREAKTHROUGH: >500 MB/s achieved!\n", .{});
    } else if (mb_per_sec > 300) {
        try stdout.print("  ⚡ GOOD: >300 MB/s achieved!\n", .{});
    } else {
        try stdout.print("  📈 Still optimizing...\n", .{});
    }
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
            indent, indent, id, 
            indent, id, 
            indent, id, 
            indent, if (id % 2 == 0) "true" else "false",
            indent,
            indent, id % 100, id % 10,
            indent,
        });
        defer allocator.free(user);
        
        try result.appendSlice(user);
        current_size = result.items.len;
        id += 1;
    }
    
    try result.appendSlice("\n  ]\n}\n");
    return result.toOwnedSlice();
}