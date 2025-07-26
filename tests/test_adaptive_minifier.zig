// Test adaptive chunk size minifier
const std = @import("std");
const TurboMinifierAdaptive = @import("src/modes/turbo_minifier_adaptive.zig").TurboMinifierAdaptive;
const TurboMinifierParallelSimple = @import("src/modes/turbo_minifier_parallel_simple.zig").TurboMinifierParallelSimple;
const AdaptiveChunking = @import("src/performance/adaptive_chunking.zig").AdaptiveChunking;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n🧠 Adaptive Chunk Size Minifier Test\n", .{});
    try stdout.print("====================================\n\n", .{});
    
    // Test different file sizes
    const test_cases = [_]struct { size: usize, name: []const u8 }{
        .{ .size = 1024 * 1024, .name = "1 MB" },
        .{ .size = 10 * 1024 * 1024, .name = "10 MB" },
        .{ .size = 50 * 1024 * 1024, .name = "50 MB" },
        .{ .size = 100 * 1024 * 1024, .name = "100 MB" },
    };
    
    const thread_counts = [_]usize{ 4, 8, 16 };
    
    for (test_cases) |test_case| {
        try stdout.print("🔍 Testing {s} file:\n", .{test_case.name});
        
        const input = try generateTestJson(allocator, test_case.size);
        defer allocator.free(input);
        
        for (thread_counts) |thread_count| {
            const cpu_count = try std.Thread.getCpuCount();
            if (thread_count > cpu_count) continue;
            
            try stdout.print("\n  📊 {d} threads:\n", .{thread_count});
            
            // Show adaptive chunking decision
            const optimal_chunk_size = AdaptiveChunking.calculateOptimalChunkSize(test_case.size, thread_count);
            const estimate = AdaptiveChunking.getPerformanceEstimate(test_case.size, thread_count, optimal_chunk_size);
            
            try stdout.print("    Optimal chunk size: {d} KB\n", .{optimal_chunk_size / 1024});
            try stdout.print("    Estimated throughput: {d:.1} MB/s\n", .{estimate.estimated_throughput_mb_s});
            try stdout.print("    Chunk efficiency: {d:.1}%\n", .{estimate.chunk_efficiency * 100});
            try stdout.print("    Thread efficiency: {d:.1}%\n", .{estimate.thread_efficiency * 100});
            
            const output_adaptive = try allocator.alloc(u8, input.len);
            defer allocator.free(output_adaptive);
            const output_simple = try allocator.alloc(u8, input.len);
            defer allocator.free(output_simple);
            
            // Test adaptive implementation
            var adaptive = try TurboMinifierAdaptive.init(allocator, .{ .thread_count = thread_count });
            defer adaptive.deinit();
            
            const adaptive_start = std.time.nanoTimestamp();
            const adaptive_len = try adaptive.minify(input, output_adaptive);
            const adaptive_end = std.time.nanoTimestamp();
            const adaptive_ns = @as(u64, @intCast(adaptive_end - adaptive_start));
            const adaptive_ms = adaptive_ns / 1_000_000;
            const adaptive_throughput = if (adaptive_ms > 0)
                (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(adaptive_ms)) * 1000.0 / (1024.0 * 1024.0))
            else
                0.0;
            
            // Test simple parallel for comparison
            var simple = try TurboMinifierParallelSimple.init(allocator, .{ .thread_count = thread_count });
            defer simple.deinit();
            
            const simple_start = std.time.nanoTimestamp();
            const simple_len = try simple.minify(input, output_simple);
            const simple_end = std.time.nanoTimestamp();
            const simple_ns = @as(u64, @intCast(simple_end - simple_start));
            const simple_ms = simple_ns / 1_000_000;
            const simple_throughput = if (simple_ms > 0)
                (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(simple_ms)) * 1000.0 / (1024.0 * 1024.0))
            else
                0.0;
            
            const improvement = if (simple_throughput > 0)
                ((adaptive_throughput - simple_throughput) / simple_throughput * 100.0)
            else
                0.0;
            
            const match = (adaptive_len == simple_len);
            
            try stdout.print("    \n", .{});
            try stdout.print("    Adaptive:      {d:>7.1} MB/s ({d:>4} ms)\n", .{ adaptive_throughput, adaptive_ms });
            try stdout.print("    Simple:        {d:>7.1} MB/s ({d:>4} ms)\n", .{ simple_throughput, simple_ms });
            try stdout.print("    Improvement:   {d:>7.1}% {s}\n", .{ improvement, if (match) "✅" else "❌" });
            
            // Show accuracy of estimate
            const estimate_accuracy = if (estimate.estimated_throughput_mb_s > 0)
                (adaptive_throughput / estimate.estimated_throughput_mb_s)
            else
                0.0;
            try stdout.print("    Estimate accuracy: {d:.2}x\n", .{estimate_accuracy});
        }
        
        try stdout.print("\n", .{});
    }
    
    // Test chunk size analysis
    try testChunkSizeAnalysis(allocator);
}

fn testChunkSizeAnalysis(_: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("📈 Chunk Size Analysis\n", .{});
    try stdout.print("======================\n\n", .{});
    
    const file_sizes = [_]usize{ 1024 * 1024, 10 * 1024 * 1024, 100 * 1024 * 1024 };
    const thread_counts = [_]usize{ 4, 8, 16 };
    
    for (file_sizes) |file_size| {
        try stdout.print("File size: {d} MB\n", .{file_size / 1024 / 1024});
        try stdout.print("Threads | Optimal Chunk | Est. Throughput | Efficiency\n", .{});
        try stdout.print("--------|---------------|-----------------|------------\n", .{});
        
        for (thread_counts) |thread_count| {
            const cpu_count = try std.Thread.getCpuCount();
            if (thread_count > cpu_count) continue;
            
            const chunk_size = AdaptiveChunking.calculateOptimalChunkSize(file_size, thread_count);
            const estimate = AdaptiveChunking.getPerformanceEstimate(file_size, thread_count, chunk_size);
            
            try stdout.print("{d:>7} | {d:>11} KB | {d:>13.1} MB/s | {d:>8.1}%\n", .{
                thread_count,
                chunk_size / 1024,
                estimate.estimated_throughput_mb_s,
                estimate.chunk_efficiency * estimate.thread_efficiency * 100,
            });
        }
        
        try stdout.print("\n", .{});
    }
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
        
        const pattern = key_counter % 5;
        switch (pattern) {
            0 => try buffer.writer().print("  \"key_{d}\"  :  \"value with    spaces    and more\"", .{key_counter}),
            1 => try buffer.writer().print("  \"data_{d}\" : {{   \"num\" :   {d},   \"str\" : \"test\"   }}", .{key_counter, key_counter * 42}),
            2 => try buffer.writer().print("  \"array_{d}\" : [  1,   2,    3,     4,      5  ]", .{key_counter}),
            3 => try buffer.writer().print("  \"nested_{d}\" : {{  \"a\" : {{  \"b\" :  \"c\"  }}  }}", .{key_counter}),
            4 => try buffer.writer().print("  \"long_string_{d}\" : \"This is a longer string value that contains more content and helps test different patterns in the JSON\"", .{key_counter}),
            else => unreachable,
        }
        
        key_counter += 1;
    }
    
    try buffer.appendSlice("\n}");
    return buffer.toOwnedSlice();
}