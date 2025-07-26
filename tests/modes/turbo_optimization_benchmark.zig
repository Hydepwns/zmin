// Benchmark to test TURBO mode optimizations

const std = @import("std");
const modes = @import("modes");
const MinifierInterface = @import("minifier_interface").MinifierInterface;
const TurboMinifier = @import("turbo_minifier").TurboMinifier;
const TurboMinifierOptimized = @import("turbo_minifier_optimized").TurboMinifierOptimized;
const TurboMinifierV3 = @import("turbo_minifier_v3").TurboMinifierV3;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("=== TURBO Mode Optimization Benchmark ===\n\n", .{});
    
    // Test with different JSON patterns
    const test_cases = [_]struct { name: []const u8, json: []const u8 }{
        .{ .name = "Simple Object", .json = 
            \\{  "name"  :  "John Doe"  ,  "age"  :  30  ,  "active"  :  true  }
        },
        .{ .name = "Nested Objects", .json = 
            \\{
            \\  "user": {
            \\    "profile": {
            \\      "name": "Jane",
            \\      "settings": {
            \\        "theme": "dark",
            \\        "notifications": true
            \\      }
            \\    }
            \\  }
            \\}
        },
        .{ .name = "Array Heavy", .json = 
            \\{
            \\  "data": [
            \\    { "id": 1, "value": "first" },
            \\    { "id": 2, "value": "second" },
            \\    { "id": 3, "value": "third" },
            \\    { "id": 4, "value": "fourth" },
            \\    { "id": 5, "value": "fifth" }
            \\  ]
            \\}
        },
        .{ .name = "String Heavy", .json = 
            \\{
            \\  "title": "This is a long title with many words",
            \\  "description": "This is an even longer description that contains multiple sentences. It has punctuation, numbers like 123, and special characters!",
            \\  "content": "The main content goes here and can be quite extensive."
            \\}
        },
    };
    
    // First, test correctness
    try stdout.print("Testing correctness...\n", .{});
    for (test_cases) |tc| {
        const v1_result = try minifyV1(allocator, tc.json);
        defer allocator.free(v1_result);
        const v2_result = try minifyV2(allocator, tc.json);
        defer allocator.free(v2_result);
        
        if (!std.mem.eql(u8, v1_result, v2_result)) {
            try stdout.print("ERROR: Results differ for {s}\n", .{tc.name});
            try stdout.print("V1: {s}\n", .{v1_result});
            try stdout.print("V2: {s}\n", .{v2_result});
        } else {
            try stdout.print("✓ {s}: Results match\n", .{tc.name});
        }
    }
    
    try stdout.print("\n", .{});
    
    // Generate large test data
    const sizes = [_]usize{ 1024, 10 * 1024, 100 * 1024, 1024 * 1024, 10 * 1024 * 1024 };
    const size_names = [_][]const u8{ "1KB", "10KB", "100KB", "1MB", "10MB" };
    
    for (sizes, size_names) |size, size_name| {
        try stdout.print("Testing {s}...\n", .{size_name});
        
        const test_json = try generateTestJson(allocator, size);
        defer allocator.free(test_json);
        
        // Benchmark V1
        var v1_total: u64 = 0;
        const v1_runs: usize = if (size > 1024 * 1024) 3 else 10;
        for (0..v1_runs) |_| {
            var timer = try std.time.Timer.start();
            const result = try minifyV1(allocator, test_json);
            const elapsed = timer.read();
            allocator.free(result);
            v1_total += elapsed;
        }
        const v1_avg = v1_total / v1_runs;
        const v1_throughput = (@as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(v1_avg))) * 1000.0;
        
        // Benchmark V2
        var v2_total: u64 = 0;
        const v2_runs: usize = if (size > 1024 * 1024) 3 else 10;
        for (0..v2_runs) |_| {
            var timer = try std.time.Timer.start();
            const result = try minifyV2(allocator, test_json);
            const elapsed = timer.read();
            allocator.free(result);
            v2_total += elapsed;
        }
        const v2_avg = v2_total / v2_runs;
        const v2_throughput = (@as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(v2_avg))) * 1000.0;
        
        // Results
        try stdout.print("  V1 (original): {d:.2} MB/s\n", .{v1_throughput});
        try stdout.print("  V3 (aggressive): {d:.2} MB/s\n", .{v2_throughput});
        try stdout.print("  Speedup: {d:.2}x\n\n", .{v2_throughput / v1_throughput});
    }
}

fn minifyV1(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var minifier = TurboMinifier.init(allocator);
    const output = try allocator.alloc(u8, input.len);
    const len = try minifier.minify(input, output);
    return try allocator.realloc(output, len);
}

fn minifyV2(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var minifier = TurboMinifierV3.init(allocator);
    const output = try allocator.alloc(u8, input.len);
    const len = try minifier.minify(input, output);
    return try allocator.realloc(output, len);
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