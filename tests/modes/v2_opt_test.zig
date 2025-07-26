const std = @import("std");
const TurboMinifierOptimizedV2 = @import("turbo_minifier_optimized_v2").TurboMinifierOptimizedV2;
const TurboMinifierTable = @import("turbo_minifier_optimized_v2").TurboMinifierTable;
const TurboMinifierScalar = @import("turbo_minifier_scalar").TurboMinifierScalar;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== TURBO V2 Optimizations Test ===\n\n", .{});
    
    // Test with different patterns
    const test_cases = [_]struct { name: []const u8, json: []const u8 }{
        .{ .name = "Simple", .json = 
            \\{  "name"  :  "test"  ,  "value"  :  123  }
        },
        .{ .name = "String heavy", .json = 
            \\{"title":"This is a long string","desc":"Another string","content":"More string content"}
        },
        .{ .name = "Whitespace heavy", .json = 
            \\{
            \\    "user": {
            \\        "name": "John",
            \\        "age": 30
            \\    }
            \\}
        },
    };
    
    // Correctness test
    try stdout.print("Correctness tests:\n", .{});
    for (test_cases) |tc| {
        const scalar_result = try testScalar(allocator, tc.json);
        defer allocator.free(scalar_result);
        const v2_result = try testV2(allocator, tc.json);
        defer allocator.free(v2_result);
        const table_result = try testTable(allocator, tc.json);
        defer allocator.free(table_result);
        
        const match_v2 = std.mem.eql(u8, scalar_result, v2_result);
        const match_table = std.mem.eql(u8, scalar_result, table_result);
        
        try stdout.print("  {s}: V2={s}, Table={s}\n", .{
            tc.name,
            if (match_v2) "✓" else "✗",
            if (match_table) "✓" else "✗",
        });
    }
    
    // Performance test
    try stdout.print("\nPerformance comparison (1MB files):\n", .{});
    
    const sizes = [_]usize{ 1024 * 1024, 10 * 1024 * 1024 };
    const size_names = [_][]const u8{ "1MB", "10MB" };
    
    for (sizes, size_names) |size, size_name| {
        try stdout.print("\n{s} test:\n", .{size_name});
        
        // Normal JSON
        {
            const test_json = try generateTestJson(allocator, size);
            defer allocator.free(test_json);
            
            const scalar_tp = try benchmarkMinifier(allocator, test_json, testScalarBench);
            const v2_tp = try benchmarkMinifier(allocator, test_json, testV2Bench);
            const table_tp = try benchmarkMinifier(allocator, test_json, testTableBench);
            
            try stdout.print("  Normal JSON:\n", .{});
            try stdout.print("    Scalar: {d:.2} MB/s\n", .{scalar_tp});
            try stdout.print("    V2 Opt: {d:.2} MB/s ({d:.1}x)\n", .{v2_tp, v2_tp / scalar_tp});
            try stdout.print("    Table:  {d:.2} MB/s ({d:.1}x)\n", .{table_tp, table_tp / scalar_tp});
        }
        
        // String heavy
        {
            const test_json = try generateStringHeavyJson(allocator, size);
            defer allocator.free(test_json);
            
            const scalar_tp = try benchmarkMinifier(allocator, test_json, testScalarBench);
            const v2_tp = try benchmarkMinifier(allocator, test_json, testV2Bench);
            
            try stdout.print("  String heavy:\n", .{});
            try stdout.print("    Scalar: {d:.2} MB/s\n", .{scalar_tp});
            try stdout.print("    V2 Opt: {d:.2} MB/s ({d:.1}x)\n", .{v2_tp, v2_tp / scalar_tp});
            
            if (v2_tp > 500) {
                try stdout.print("\n🚀 BREAKTHROUGH: {d:.2} MB/s achieved!\n", .{v2_tp});
            }
        }
    }
}

fn benchmarkMinifier(allocator: std.mem.Allocator, input: []const u8, minify_fn: anytype) !f64 {
    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);
    
    // Warm up
    _ = try minify_fn(allocator, input, output);
    
    const runs: usize = if (input.len > 1024 * 1024) 3 else 10;
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

// Test functions
fn testScalar(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var minifier = TurboMinifierScalar.init(allocator);
    const output = try allocator.alloc(u8, input.len);
    const len = try minifier.minify(input, output);
    return try allocator.realloc(output, len);
}

fn testV2(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var minifier = TurboMinifierOptimizedV2.init(allocator);
    const output = try allocator.alloc(u8, input.len);
    const len = try minifier.minify(input, output);
    return try allocator.realloc(output, len);
}

fn testTable(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var minifier = TurboMinifierTable.init(allocator);
    const output = try allocator.alloc(u8, input.len);
    const len = try minifier.minify(input, output);
    return try allocator.realloc(output, len);
}

fn testScalarBench(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierScalar.init(allocator);
    return minifier.minify(input, output);
}

fn testV2Bench(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierOptimizedV2.init(allocator);
    return minifier.minify(input, output);
}

fn testTableBench(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierTable.init(allocator);
    return minifier.minify(input, output);
}

// JSON generators
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

fn generateStringHeavyJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    
    try result.appendSlice("{\"strings\":[");
    
    while (result.items.len < target_size - 200) {
        try result.appendSlice("\"This is a long string with many words to test string processing performance\",");
    }
    
    try result.appendSlice("\"final string\"]}");
    return result.toOwnedSlice();
}