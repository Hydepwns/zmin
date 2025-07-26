const std = @import("std");
const TurboMinifierScalar = @import("turbo_minifier_scalar").TurboMinifierScalar;
const TurboMinifierBranchless = @import("turbo_minifier_scalar").TurboMinifierBranchless;
const TurboMinifierV3 = @import("turbo_minifier_v3").TurboMinifierV3;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== TURBO Scalar vs SIMD Comparison ===\n\n", .{});
    
    // Generate test data
    const test_json = try generateTestJson(allocator, 1024 * 1024);
    defer allocator.free(test_json);
    
    try stdout.print("Testing on {} bytes...\n\n", .{test_json.len});
    
    // Test V3 (SIMD baseline)
    try stdout.print("Testing V3 (SIMD)...\n", .{});
    const v3_result = try testMinifier(allocator, test_json, testV3);
    try stdout.print("  Throughput: {d:.2} MB/s\n", .{v3_result.throughput});
    try stdout.print("  Time: {d:.2} ms\n\n", .{v3_result.time_ms});
    
    // Test Scalar optimized
    try stdout.print("Testing Scalar Optimized...\n", .{});
    const scalar_result = try testMinifier(allocator, test_json, testScalar);
    try stdout.print("  Throughput: {d:.2} MB/s\n", .{scalar_result.throughput});
    try stdout.print("  Time: {d:.2} ms\n", .{scalar_result.time_ms});
    try stdout.print("  Speedup vs V3: {d:.2}x\n\n", .{scalar_result.throughput / v3_result.throughput});
    
    // Test Branchless
    try stdout.print("Testing Branchless...\n", .{});
    const branchless_result = try testMinifier(allocator, test_json, testBranchless);
    try stdout.print("  Throughput: {d:.2} MB/s\n", .{branchless_result.throughput});
    try stdout.print("  Time: {d:.2} ms\n", .{branchless_result.time_ms});
    try stdout.print("  Speedup vs V3: {d:.2}x\n\n", .{branchless_result.throughput / v3_result.throughput});
    
    // Summary
    try stdout.print("=== SUMMARY ===\n", .{});
    const best_throughput = @max(v3_result.throughput, @max(scalar_result.throughput, branchless_result.throughput));
    
    if (best_throughput > 500) {
        try stdout.print("🚀 BREAKTHROUGH: {d:.2} MB/s achieved!\n", .{best_throughput});
        if (best_throughput > 800) {
            try stdout.print("🎯 TARGET REACHED: Exceeding roadmap 800 MB/s!\n", .{});
        }
    } else if (best_throughput > 300) {
        try stdout.print("⚡ PROGRESS: {d:.2} MB/s (approaching target)\n", .{best_throughput});
    } else {
        try stdout.print("📈 Current best: {d:.2} MB/s\n", .{best_throughput});
    }
}

const TestResult = struct {
    throughput: f64,
    time_ms: f64,
};

fn testMinifier(allocator: std.mem.Allocator, input: []const u8, minify_fn: anytype) !TestResult {
    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);
    
    // Warm up
    _ = try minify_fn(allocator, input, output);
    
    // Benchmark
    var total_time: u64 = 0;
    const runs = 10;
    
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
    const time_ms = @as(f64, @floatFromInt(avg_time)) / 1_000_000.0;
    
    return TestResult{
        .throughput = mb_per_sec,
        .time_ms = time_ms,
    };
}

fn testV3(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierV3.init(allocator);
    return minifier.minify(input, output);
}

fn testScalar(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierScalar.init(allocator);
    return minifier.minify(input, output);
}

fn testBranchless(allocator: std.mem.Allocator, input: []const u8, output: []u8) !usize {
    var minifier = TurboMinifierBranchless.init(allocator);
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