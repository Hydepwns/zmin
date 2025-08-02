//! Phase 2 Performance Benchmark
//!
//! Tests the algorithmic revolution improvements:
//! - SimdJSON-inspired two-stage architecture
//! - Cache hierarchy optimization
//! - Prefetching and chunked processing
//!
//! Target: 1.2 GB/s throughput

const std = @import("std");
const modes = @import("modes");
const TurboMinifier = @import("turbo_unified").TurboMinifier;
const TurboConfig = @import("turbo_unified").TurboConfig;

const BENCHMARK_ITERATIONS = 10;
const MB = 1024 * 1024;

/// Test configuration
const TestConfig = struct {
    name: []const u8,
    size: usize,
    description: []const u8,
};

/// Test cases for different file sizes
const test_configs = [_]TestConfig{
    .{ .name = "tiny", .size = 1 * 1024, .description = "1 KB - L1 cache resident" },
    .{ .name = "small", .size = 32 * 1024, .description = "32 KB - L1 cache size" },
    .{ .name = "medium", .size = 256 * 1024, .description = "256 KB - L2 cache size" },
    .{ .name = "large", .size = 1 * MB, .description = "1 MB - Partial L3" },
    .{ .name = "huge", .size = 10 * MB, .description = "10 MB - Exceeds L3" },
};

/// Generate realistic JSON test data
fn generateTestJson(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);
    defer json.deinit();
    
    try json.appendSlice("{\n  \"data\": [\n");
    
    var current_size: usize = json.items.len;
    var item_count: usize = 0;
    
    while (current_size < size * 9 / 10) { // Leave room for closing
        if (item_count > 0) {
            try json.appendSlice(",\n");
        }
        
        try json.appendSlice("    {\n");
        try json.writer().print("      \"id\": {},\n", .{item_count});
        try json.writer().print("      \"name\": \"Item {}\",\n", .{item_count});
        try json.appendSlice("      \"description\": \"This is a longer description with    spaces    and\n      newlines\n      that should be minified\",\n");
        try json.writer().print("      \"value\": {d:.2},\n", .{@as(f64, @floatFromInt(item_count)) * 3.14159});
        try json.appendSlice("      \"tags\": [\"tag1\", \"tag2\", \"tag3\"],\n");
        try json.appendSlice("      \"nested\": {\n");
        try json.appendSlice("        \"field1\": \"value1\",\n");
        try json.appendSlice("        \"field2\": \"value2\"\n");
        try json.appendSlice("      }\n");
        try json.appendSlice("    }");
        
        item_count += 1;
        current_size = json.items.len;
    }
    
    try json.appendSlice("\n  ]\n}\n");
    
    // Pad to exact size if needed
    while (json.items.len < size) {
        try json.append(' ');
    }
    
    return json.toOwnedSlice();
}

/// Run benchmark for a specific configuration
fn runBenchmark(allocator: std.mem.Allocator, config: TestConfig) !void {
    std.debug.print("\n=== {s} ({s}) ===\n", .{ config.name, config.description });
    
    // Generate test data
    const input = try generateTestJson(allocator, config.size);
    defer allocator.free(input);
    
    // Test different strategies
    const strategies = [_]struct { name: []const u8, enable_simd: bool }{
        .{ .name = "Scalar", .enable_simd = false },
        .{ .name = "SIMD", .enable_simd = true },
    };
    
    for (strategies) |strategy| {
        var total_time: i64 = 0;
        var min_time: i64 = std.math.maxInt(i64);
        var max_time: i64 = 0;
        var total_compression: f64 = 0;
        
        // Warm up
        {
            var minifier = try TurboMinifier.init(allocator);
            const result = try minifier.minify(input, .{ .enable_simd = strategy.enable_simd });
            allocator.free(result.output);
        }
        
        // Run benchmark iterations
        var i: usize = 0;
        while (i < BENCHMARK_ITERATIONS) : (i += 1) {
            var minifier = try TurboMinifier.init(allocator);
            
            const start = std.time.microTimestamp();
            const result = try minifier.minify(input, .{ .enable_simd = strategy.enable_simd });
            const end = std.time.microTimestamp();
            
            const duration = end - start;
            total_time += duration;
            min_time = @min(min_time, duration);
            max_time = @max(max_time, duration);
            total_compression += result.compression_ratio;
            
            allocator.free(result.output);
        }
        
        // Calculate statistics
        const avg_time = @as(f64, @floatFromInt(total_time)) / @as(f64, BENCHMARK_ITERATIONS);
        const avg_compression = total_compression / @as(f64, BENCHMARK_ITERATIONS);
        
        // Calculate throughput
        const size_mb = @as(f64, @floatFromInt(config.size)) / @as(f64, MB);
        const avg_time_s = avg_time / 1_000_000.0;
        const throughput_mbps = size_mb / avg_time_s;
        const throughput_gbps = throughput_mbps / 1024.0;
        
        // Print results
        std.debug.print("  {s} Strategy:\n", .{strategy.name});
        std.debug.print("    Average time: {d:.2} ms\n", .{avg_time / 1000.0});
        std.debug.print("    Min time: {d:.2} ms\n", .{@as(f64, @floatFromInt(min_time)) / 1000.0});
        std.debug.print("    Max time: {d:.2} ms\n", .{@as(f64, @floatFromInt(max_time)) / 1000.0});
        std.debug.print("    Throughput: {d:.2} MB/s ({d:.3} GB/s)\n", .{ throughput_mbps, throughput_gbps });
        std.debug.print("    Compression ratio: {d:.1}%\n", .{avg_compression * 100});
    }
}

/// Check if AVX-512 is available
fn checkAvx512Support() bool {
    const builtin = @import("builtin");
    if (builtin.cpu.arch != .x86_64) return false;
    
    const cpu = builtin.cpu;
    return std.Target.x86.featureSetHas(cpu.features, .avx512f) and
           std.Target.x86.featureSetHas(cpu.features, .avx512bw) and
           std.Target.x86.featureSetHas(cpu.features, .avx512vl);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n🚀 zmin Phase 2 Performance Benchmark\n", .{});
    std.debug.print("=====================================\n", .{});
    std.debug.print("Target: 1.2 GB/s throughput\n", .{});
    std.debug.print("Iterations per test: {}\n", .{BENCHMARK_ITERATIONS});
    
    // Check CPU features
    std.debug.print("\nCPU Features:\n", .{});
    std.debug.print("  AVX-512: {}\n", .{checkAvx512Support()});
    
    // Run benchmarks for each configuration
    for (test_configs) |config| {
        try runBenchmark(allocator, config);
    }
    
    std.debug.print("\n✅ Benchmark complete!\n", .{});
}

test "phase 2 performance improvements" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test with 1MB file
    const input = try generateTestJson(allocator, 1 * MB);
    defer allocator.free(input);
    
    var minifier = try TurboMinifier.init(allocator);
    
    // Benchmark with SIMD enabled
    const start = std.time.microTimestamp();
    const result = try minifier.minify(input, .{ .enable_simd = true });
    const end = std.time.microTimestamp();
    defer allocator.free(result.output);
    
    const duration_us = @as(f64, @floatFromInt(end - start));
    const size_mb = @as(f64, @floatFromInt(input.len)) / @as(f64, MB);
    const throughput_mbps = (size_mb * 1_000_000.0) / duration_us;
    
    std.debug.print("\nPhase 2 Test Result:\n", .{});
    std.debug.print("  Input size: {} bytes\n", .{input.len});
    std.debug.print("  Output size: {} bytes\n", .{result.output.len});
    std.debug.print("  Compression: {d:.1}%\n", .{result.compression_ratio * 100});
    std.debug.print("  Time: {d:.2} ms\n", .{duration_us / 1000.0});
    std.debug.print("  Throughput: {d:.2} MB/s\n", .{throughput_mbps});
    
    // Verify correctness
    try std.testing.expect(result.output.len < input.len);
    try std.testing.expect(result.compression_ratio > 0);
}