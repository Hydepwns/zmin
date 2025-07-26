// TURBO mode performance benchmark

const std = @import("std");
const modes = @import("modes");
const MinifierInterface = @import("minifier_interface").MinifierInterface;
const cpu_detection = @import("cpu_detection");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("=== TURBO Mode Performance Benchmark ===\n\n", .{});
    
    // Show CPU features
    const cpu_info = cpu_detection.CpuInfo.init();
    try stdout.print("CPU Information:\n", .{});
    try stdout.print("  {}\n", .{cpu_info});
    
    const strategy = cpu_detection.getOptimalSimdStrategy();
    try stdout.print("  Optimal SIMD Strategy: {s}\n", .{@tagName(strategy)});
    try stdout.print("  Vector Width: {} bytes\n\n", .{strategy.getSimdWidth()});
    
    // Test different file sizes
    const test_sizes = [_]struct { name: []const u8, size: usize }{
        .{ .name = "Small (1KB)", .size = 1024 },
        .{ .name = "Medium (100KB)", .size = 100 * 1024 },
        .{ .name = "Large (1MB)", .size = 1024 * 1024 },
        .{ .name = "Huge (10MB)", .size = 10 * 1024 * 1024 },
        .{ .name = "Massive (100MB)", .size = 100 * 1024 * 1024 },
    };
    
    for (test_sizes) |test_case| {
        try stdout.print("Testing {s}...\n", .{test_case.name});
        
        // Generate test JSON
        const input = try generateTestJson(allocator, test_case.size);
        defer allocator.free(input);
        
        // Warm up
        _ = try MinifierInterface.minifyString(allocator, .turbo, input);
        
        // Benchmark all three modes
        const modes_to_test = [_]modes.ProcessingMode{ .eco, .sport, .turbo };
        
        for (modes_to_test) |mode| {
            const runs: usize = if (test_case.size > 10 * 1024 * 1024) 3 else 10;
            var total_time: u64 = 0;
            var min_time: u64 = std.math.maxInt(u64);
            var max_time: u64 = 0;
            
            for (0..runs) |_| {
                var timer = try std.time.Timer.start();
                const result = try MinifierInterface.minifyString(allocator, mode, input);
                const elapsed = timer.read();
                allocator.free(result);
                
                total_time += elapsed;
                min_time = @min(min_time, elapsed);
                max_time = @max(max_time, elapsed);
            }
            
            const avg_time = total_time / runs;
            const throughput_mbps = (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(avg_time))) * 1000.0;
            const throughput_gbps = throughput_mbps / 1000.0;
            
            try stdout.print("  {} mode:\n", .{mode});
            if (throughput_mbps > 1000) {
                try stdout.print("    Average: {d:.2}ms ({d:.2} GB/s)\n", .{
                    @as(f64, @floatFromInt(avg_time)) / 1_000_000.0,
                    throughput_gbps,
                });
            } else {
                try stdout.print("    Average: {d:.2}ms ({d:.2} MB/s)\n", .{
                    @as(f64, @floatFromInt(avg_time)) / 1_000_000.0,
                    throughput_mbps,
                });
            }
            try stdout.print("    Min: {d:.2}ms, Max: {d:.2}ms\n", .{
                @as(f64, @floatFromInt(min_time)) / 1_000_000.0,
                @as(f64, @floatFromInt(max_time)) / 1_000_000.0,
            });
        }
        
        try stdout.print("\n", .{});
        
        // Don't test massive size for all modes, just TURBO
        if (test_case.size >= 100 * 1024 * 1024) break;
    }
    
    // Special TURBO-only test for very large files
    try stdout.print("TURBO Mode Scaling Test:\n", .{});
    const large_sizes = [_]usize{ 10 * 1024 * 1024, 50 * 1024 * 1024, 100 * 1024 * 1024 };
    
    for (large_sizes) |size| {
        const input = try generateTestJson(allocator, size);
        defer allocator.free(input);
        
        var timer = try std.time.Timer.start();
        const result = try MinifierInterface.minifyString(allocator, .turbo, input);
        const elapsed = timer.read();
        allocator.free(result);
        
        const throughput_gbps = (@as(f64, @floatFromInt(size)) / @as(f64, @floatFromInt(elapsed))) / 1.0;
        try stdout.print("  {}MB: {d:.2} GB/s\n", .{
            size / (1024 * 1024),
            throughput_gbps,
        });
    }
}

fn generateTestJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    
    // Create realistic JSON with mixed content
    try result.appendSlice("{\n");
    try result.appendSlice("  \"users\": [\n");
    
    var current_size: usize = result.items.len;
    var id: usize = 0;
    
    while (current_size < target_size - 100) {
        if (id > 0) {
            try result.appendSlice(",\n");
        }
        
        const user = try std.fmt.allocPrint(allocator, 
            \\    {{
            \\      "id": {d},
            \\      "name": "User {d}",
            \\      "email": "user{d}@example.com",
            \\      "active": {s},
            \\      "score": {d}.{d}
            \\    }}
        , .{ 
            id, 
            id, 
            id, 
            if (id % 2 == 0) "true" else "false",
            id % 100,
            id % 10,
        });
        defer allocator.free(user);
        
        try result.appendSlice(user);
        current_size = result.items.len;
        id += 1;
    }
    
    try result.appendSlice("\n  ]\n}\n");
    return result.toOwnedSlice();
}