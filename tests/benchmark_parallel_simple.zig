// Benchmark for simple parallel implementation
const std = @import("std");

// Copy implementations
const TurboMinifierParallelSimple = @import("src/modes/turbo_minifier_parallel_simple.zig").TurboMinifierParallelSimple;
const TurboMinifierSimple = @import("src/modes/turbo_minifier_simple.zig").TurboMinifierSimple;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n🏁 Simple Parallel Implementation Benchmark\n", .{});
    try stdout.print("==========================================\n\n", .{});
    
    // Test sizes
    const test_sizes = [_]struct { size: usize, name: []const u8 }{
        .{ .size = 1024 * 1024, .name = "1 MB" },
        .{ .size = 10 * 1024 * 1024, .name = "10 MB" },
        .{ .size = 50 * 1024 * 1024, .name = "50 MB" },
        .{ .size = 100 * 1024 * 1024, .name = "100 MB" },
    };
    
    const thread_counts = [_]usize{ 1, 2, 4, 8 };
    
    for (test_sizes) |test_case| {
        try stdout.print("📊 Testing {s} file:\n", .{test_case.name});
        
        const input = try generateTestJson(allocator, test_case.size);
        defer allocator.free(input);
        
        const output = try allocator.alloc(u8, input.len);
        defer allocator.free(output);
        
        // Baseline with simple implementation
        var simple = TurboMinifierSimple.init(allocator);
        
        const simple_start = std.time.nanoTimestamp();
        const simple_len = try simple.minify(input, output);
        const simple_end = std.time.nanoTimestamp();
        const simple_ns = @as(u64, @intCast(simple_end - simple_start));
        const simple_ms = simple_ns / 1_000_000;
        const simple_throughput = if (simple_ms > 0) 
            (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(simple_ms)) * 1000.0 / (1024.0 * 1024.0))
        else 
            0.0;
        
        try stdout.print("  Single-threaded: {d:>5} ms ({d:>7.1} MB/s)\n", .{ simple_ms, simple_throughput });
        
        // Test different thread counts
        for (thread_counts) |thread_count| {
            const cpu_count = try std.Thread.getCpuCount();
            if (thread_count > cpu_count) continue;
            
            var parallel = try TurboMinifierParallelSimple.init(allocator, .{ .thread_count = thread_count });
            defer parallel.deinit();
            
            // Warm up
            _ = try parallel.minify(input[0..@min(1024, input.len)], output);
            
            // Actual benchmark
            const parallel_start = std.time.nanoTimestamp();
            const parallel_len = try parallel.minify(input, output);
            const parallel_end = std.time.nanoTimestamp();
            const parallel_ns = @as(u64, @intCast(parallel_end - parallel_start));
            const parallel_ms = parallel_ns / 1_000_000;
            const parallel_throughput = if (parallel_ms > 0) 
                (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(parallel_ms)) * 1000.0 / (1024.0 * 1024.0))
            else 
                0.0;
            
            const speedup = if (parallel_ms > 0) 
                @as(f64, @floatFromInt(simple_ms)) / @as(f64, @floatFromInt(parallel_ms))
            else 
                0.0;
            
            const match = (simple_len == parallel_len);
            
            try stdout.print("  {d} threads:       {d:>5} ms ({d:>7.1} MB/s) - {d:.2}x speedup {s}\n", .{
                thread_count,
                parallel_ms,
                parallel_throughput,
                speedup,
                if (match) "✅" else "❌"
            });
        }
        
        try stdout.print("\n", .{});
    }
    
    try stdout.print("✨ Benchmark complete!\n", .{});
}

fn generateTestJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    try buffer.appendSlice("{\n");
    
    var key_counter: usize = 0;
    while (buffer.items.len < target_size - 100) {
        if (key_counter > 0) {
            try buffer.appendSlice(",\n");
        }
        
        const pattern = key_counter % 4;
        switch (pattern) {
            0 => try buffer.writer().print("  \"key_{d}\"  :  \"value with    spaces    and more\"", .{key_counter}),
            1 => try buffer.writer().print("  \"data_{d}\" : {{   \"num\" :   {d},   \"str\" : \"test\"   }}", .{key_counter, key_counter * 42}),
            2 => try buffer.writer().print("  \"array_{d}\" : [  1,   2,    3,     4,      5  ]", .{key_counter}),
            3 => try buffer.writer().print("  \"nested_{d}\" : {{  \"a\" : {{  \"b\" :  \"c\"  }}  }}", .{key_counter}),
            else => unreachable,
        }
        
        key_counter += 1;
    }
    
    try buffer.appendSlice("\n}");
    return buffer.toOwnedSlice();
}