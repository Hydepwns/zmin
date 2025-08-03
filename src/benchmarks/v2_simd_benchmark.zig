const std = @import("std");
const StreamingParser = @import("../src/v2/streaming/parser.zig").StreamingParser;
const ParserConfig = @import("../src/v2/streaming/parser.zig").ParserConfig;
const SimdLevel = @import("../src/v2/streaming/parser.zig").SimdLevel;

const BenchmarkResult = struct {
    name: []const u8,
    throughput_mbps: f64,
    time_ns: u64,
    bytes_processed: usize,
    tokens_found: usize,
};

fn generateTestData(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try buf.appendSlice("{\n");
    
    const items_count = size / 100; // Approximate items to reach target size
    for (0..items_count) |i| {
        try buf.writer().print(
            \\  "item_{}": {{
            \\    "id": {},
            \\    "active": {},
            \\    "value": {},
            \\    "tags": [
        , .{ i, i, if (i % 3 == 0) "true" else "false", if (i % 5 == 0) "null" else "123.45" });
        
        // Add some array elements
        for (0..5) |j| {
            try buf.writer().print("{}", .{if (j % 2 == 0) "true" else "false"});
            if (j < 4) try buf.appendSlice(", ");
        }
        
        try buf.appendSlice("],\n");
        try buf.writer().print(
            \\    "nested": {{
            \\      "flag": {},
            \\      "empty": {}
            \\    }}
            \\  }}
        , .{ if (i % 2 == 0) "true" else "false", if (i % 4 == 0) "null" else "42" });
        
        if (i < items_count - 1) {
            try buf.appendSlice(",\n");
        } else {
            try buf.appendSlice("\n");
        }
    }
    
    try buf.appendSlice("}");
    
    return allocator.dupe(u8, buf.items);
}

fn benchmarkParser(allocator: std.mem.Allocator, name: []const u8, config: ParserConfig, data: []const u8) !BenchmarkResult {
    var parser = try StreamingParser.init(allocator, config);
    defer parser.deinit();
    
    const start_time = std.time.nanoTimestamp();
    var token_stream = try parser.parseStreaming(data);
    defer token_stream.deinit();
    
    // Count tokens to ensure parsing actually happened
    var token_count: usize = 0;
    while (token_stream.hasMore()) {
        if (token_stream.getCurrentToken()) |_| {
            token_count += 1;
        }
        token_stream.advance();
    }
    
    const end_time = std.time.nanoTimestamp();
    const elapsed_ns = @as(u64, @intCast(end_time - start_time));
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
    const throughput_mbps = @as(f64, @floatFromInt(data.len)) / (1024.0 * 1024.0) / elapsed_s;
    
    return BenchmarkResult{
        .name = name,
        .throughput_mbps = throughput_mbps,
        .time_ns = elapsed_ns,
        .bytes_processed = data.len,
        .tokens_found = token_count,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test sizes
    const test_sizes = [_]usize{
        1 * 1024,       // 1 KB
        10 * 1024,      // 10 KB
        100 * 1024,     // 100 KB
        1024 * 1024,    // 1 MB
        10 * 1024 * 1024, // 10 MB
    };
    
    // SIMD configurations to test
    const configs = [_]struct { name: []const u8, config: ParserConfig }{
        .{ .name = "Scalar", .config = ParserConfig{ .enable_simd = false, .simd_level = .none } },
        .{ .name = "SSE2", .config = ParserConfig{ .enable_simd = true, .simd_level = .sse2 } },
        .{ .name = "AVX2", .config = ParserConfig{ .enable_simd = true, .simd_level = .avx2 } },
        .{ .name = "AVX-512", .config = ParserConfig{ .enable_simd = true, .simd_level = .avx512 } },
        .{ .name = "NEON", .config = ParserConfig{ .enable_simd = true, .simd_level = .neon } },
        .{ .name = "Auto", .config = ParserConfig{ .enable_simd = true, .simd_level = .auto } },
    };
    
    std.debug.print("\n=== V2.0 SIMD JSON Parser Benchmark ===\n\n", .{});
    
    for (test_sizes) |size| {
        std.debug.print("Test Size: {} KB\n", .{size / 1024});
        std.debug.print("{s:<12} {s:>15} {s:>15} {s:>15} {s:>15}\n", .{ 
            "Parser", "Time (ms)", "Throughput MB/s", "Tokens", "Speedup" 
        });
        std.debug.print("{s:-<80}\n", .{""});
        
        // Generate test data
        const data = try generateTestData(allocator, size);
        defer allocator.free(data);
        
        var scalar_time: u64 = 0;
        
        // Run benchmarks
        for (configs) |cfg| {
            // Skip platform-specific SIMD levels if not on that platform
            const builtin = @import("builtin");
            if (cfg.config.simd_level == .neon and builtin.target.cpu.arch != .aarch64) continue;
            if ((cfg.config.simd_level == .avx2 or cfg.config.simd_level == .avx512) and builtin.target.cpu.arch != .x86_64) continue;
            
            // Run multiple iterations for stability
            var total_time: u64 = 0;
            var total_throughput: f64 = 0;
            var tokens: usize = 0;
            const iterations = 5;
            
            for (0..iterations) |_| {
                const result = try benchmarkParser(allocator, cfg.name, cfg.config, data);
                total_time += result.time_ns;
                total_throughput += result.throughput_mbps;
                tokens = result.tokens_found;
            }
            
            const avg_time = total_time / iterations;
            const avg_throughput = total_throughput / @as(f64, iterations);
            
            if (cfg.config.simd_level == .none) {
                scalar_time = avg_time;
            }
            
            const speedup = if (scalar_time > 0) 
                @as(f64, @floatFromInt(scalar_time)) / @as(f64, @floatFromInt(avg_time))
            else 
                1.0;
            
            std.debug.print("{s:<12} {d:>15.2} {d:>15.2} {d:>15} {d:>15.2}x\n", .{
                cfg.name,
                @as(f64, @floatFromInt(avg_time)) / 1_000_000.0, // Convert to ms
                avg_throughput,
                tokens,
                speedup,
            });
        }
        
        std.debug.print("\n", .{});
    }
    
    // Feature-specific benchmarks
    std.debug.print("\n=== Feature-Specific Performance ===\n\n", .{});
    
    // Test with high density of literals
    {
        std.debug.print("High-density literals test (mostly true/false/null values):\n", .{});
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();
        
        try buf.appendSlice("[");
        for (0..10000) |i| {
            const value = switch (i % 3) {
                0 => "true",
                1 => "false",
                else => "null",
            };
            try buf.appendSlice(value);
            if (i < 9999) try buf.appendSlice(",");
        }
        try buf.appendSlice("]");
        
        const literal_data = buf.items;
        
        const scalar_result = try benchmarkParser(allocator, "Scalar", 
            ParserConfig{ .enable_simd = false, .simd_level = .none }, literal_data);
        const simd_result = try benchmarkParser(allocator, "SIMD Auto", 
            ParserConfig{ .enable_simd = true, .simd_level = .auto }, literal_data);
        
        std.debug.print("  Scalar: {d:.2} MB/s\n", .{scalar_result.throughput_mbps});
        std.debug.print("  SIMD:   {d:.2} MB/s (speedup: {d:.2}x)\n", .{
            simd_result.throughput_mbps,
            simd_result.throughput_mbps / scalar_result.throughput_mbps,
        });
    }
    
    std.debug.print("\n=== Benchmark Complete ===\n", .{});
}