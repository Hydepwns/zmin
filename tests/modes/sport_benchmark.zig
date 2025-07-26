// SPORT mode performance benchmark

const std = @import("std");
const modes = @import("modes");
const MinifierInterface = @import("minifier_interface").MinifierInterface;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("=== SPORT Mode Performance Benchmark ===\n\n", .{});
    
    // Test different file sizes
    const test_sizes = [_]struct { name: []const u8, size: usize }{
        .{ .name = "Small (1KB)", .size = 1024 },
        .{ .name = "Medium (100KB)", .size = 100 * 1024 },
        .{ .name = "Large (1MB)", .size = 1024 * 1024 },
        .{ .name = "Huge (10MB)", .size = 10 * 1024 * 1024 },
    };
    
    for (test_sizes) |test_case| {
        try stdout.print("Testing {s}...\n", .{test_case.name});
        
        // Generate test JSON
        const input = try generateTestJson(allocator, test_case.size);
        defer allocator.free(input);
        
        // Warm up
        _ = try MinifierInterface.minifyString(allocator, .sport, input);
        
        // Benchmark each mode
        const modes_to_test = [_]modes.ProcessingMode{ .eco, .sport };
        
        for (modes_to_test) |mode| {
            const runs = 10;
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
            
            try stdout.print("  {} mode:\n", .{mode});
            try stdout.print("    Average: {d:.2}ms ({d:.2} MB/s)\n", .{
                @as(f64, @floatFromInt(avg_time)) / 1_000_000.0,
                throughput_mbps,
            });
            try stdout.print("    Min: {d:.2}ms, Max: {d:.2}ms\n", .{
                @as(f64, @floatFromInt(min_time)) / 1_000_000.0,
                @as(f64, @floatFromInt(max_time)) / 1_000_000.0,
            });
            
            // Memory usage estimate
            const memory = MinifierInterface.getMemoryRequirement(mode, test_case.size);
            try stdout.print("    Memory: {d:.2} KB\n", .{@as(f64, @floatFromInt(memory)) / 1024.0});
        }
        
        try stdout.print("\n", .{});
    }
    
    // Special test for cache efficiency
    try stdout.print("Cache Efficiency Test (processing 1MB in different chunk sizes):\n", .{});
    const mb_size = 1024 * 1024;
    const chunk_sizes = [_]usize{ 4096, 16384, 65536, 262144, 1048576 };
    
    for (chunk_sizes) |chunk_size| {
        // Create a sport minifier with specific chunk size
        var sport_minifier = @import("sport_minifier").SportMinifier.init(allocator);
        sport_minifier.chunk_size = chunk_size;
        
        const input = try generateTestJson(allocator, mb_size);
        defer allocator.free(input);
        
        var timer = try std.time.Timer.start();
        var stream = std.io.fixedBufferStream(input);
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        
        try sport_minifier.minifyStreaming(stream.reader(), output.writer());
        const elapsed = timer.read();
        
        const throughput = (@as(f64, @floatFromInt(mb_size)) / @as(f64, @floatFromInt(elapsed))) * 1000.0;
        try stdout.print("  Chunk size {d}KB: {d:.2} MB/s\n", .{
            chunk_size / 1024,
            throughput,
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
            \\      "score": {d}.{d},
            \\      "tags": ["tag1", "tag2", "tag3"],
            \\      "metadata": {{
            \\        "created": "2024-01-01T00:00:00Z",
            \\        "updated": "2024-01-02T00:00:00Z"
            \\      }}
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