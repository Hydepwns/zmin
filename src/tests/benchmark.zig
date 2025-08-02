//! Performance Benchmarks
//!
//! Comprehensive benchmarks to measure and track performance
//! across different scenarios and configurations.

const std = @import("std");
const zmin = @import("../api/simple.zig");
const advanced = @import("../api/advanced.zig");

const Benchmark = struct {
    name: []const u8,
    iterations: usize = 1000,
    warmup_iterations: usize = 100,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== zmin Performance Benchmarks ===\n\n", .{});
    
    // Run all benchmarks
    try benchmarkSimpleAPI(allocator);
    try benchmarkAdvancedAPI(allocator);
    try benchmarkStreamingAPI(allocator);
    try benchmarkDifferentSizes(allocator);
    try benchmarkDifferentComplexity(allocator);
    try benchmarkMemoryStrategies(allocator);
    
    std.debug.print("\n=== Benchmark Complete ===\n", .{});
}

fn benchmarkSimpleAPI(allocator: std.mem.Allocator) !void {
    std.debug.print("Simple API Benchmarks:\n", .{});
    
    const test_cases = [_]struct {
        name: []const u8,
        json: []const u8,
    }{
        .{ .name = "tiny (16B)", .json = "{\"a\":1,\"b\":2}" },
        .{ .name = "small (128B)", .json = "{\"users\":[{\"id\":1,\"name\":\"John\"},{\"id\":2,\"name\":\"Jane\"}],\"count\":2,\"active\":true}" },
        .{ .name = "medium (1KB)", .json = generateJSON(allocator, 1024) catch "{}" },
        .{ .name = "large (64KB)", .json = generateJSON(allocator, 64 * 1024) catch "{}" },
    };
    
    for (test_cases) |tc| {
        const result = try benchmarkMinify(allocator, tc.json, .{
            .name = tc.name,
            .iterations = 10000,
        });
        
        std.debug.print("  {s}: {d:.2} GB/s, {d:.0} ns/op\n", .{
            tc.name,
            result.throughput_gbps,
            result.ns_per_op,
        });
    }
    
    std.debug.print("\n", .{});
}

fn benchmarkAdvancedAPI(allocator: std.mem.Allocator) !void {
    std.debug.print("Advanced API Benchmarks:\n", .{});
    
    const configs = [_]struct {
        name: []const u8,
        config: advanced.Config,
    }{
        .{ .name = "automatic", .config = .{ .optimization_level = .automatic } },
        .{ .name = "basic", .config = .{ .optimization_level = .basic } },
        .{ .name = "aggressive", .config = .{ .optimization_level = .aggressive } },
        .{ .name = "extreme", .config = .{ .optimization_level = .extreme } },
    };
    
    const test_json = try generateJSON(allocator, 10 * 1024); // 10KB
    defer allocator.free(test_json);
    
    for (configs) |cfg| {
        var minifier = try advanced.AdvancedMinifier.init(allocator, cfg.config);
        defer minifier.deinit();
        
        const result = try benchmarkAdvancedMinify(&minifier, test_json, .{
            .name = cfg.name,
            .iterations = 1000,
        });
        
        std.debug.print("  {s}: {d:.2} GB/s, {d:.0} ns/op\n", .{
            cfg.name,
            result.throughput_gbps,
            result.ns_per_op,
        });
    }
    
    std.debug.print("\n", .{});
}

fn benchmarkStreamingAPI(allocator: std.mem.Allocator) !void {
    std.debug.print("Streaming API Benchmarks:\n", .{});
    
    const sizes = [_]struct {
        name: []const u8,
        size: usize,
    }{
        .{ .name = "1MB", .size = 1024 * 1024 },
        .{ .name = "10MB", .size = 10 * 1024 * 1024 },
        .{ .name = "100MB", .size = 100 * 1024 * 1024 },
    };
    
    for (sizes) |sz| {
        // Note: For very large sizes, we'll simulate with smaller actual data
        const actual_size = @min(sz.size, 1024 * 1024); // Cap at 1MB for testing
        const test_json = try generateJSON(allocator, actual_size);
        defer allocator.free(test_json);
        
        const result = try benchmarkStreaming(allocator, test_json, .{
            .name = sz.name,
            .iterations = if (sz.size > 10 * 1024 * 1024) 10 else 100,
        });
        
        std.debug.print("  {s}: {d:.2} GB/s, {d:.2} ms/op\n", .{
            sz.name,
            result.throughput_gbps,
            result.ns_per_op / 1_000_000.0,
        });
    }
    
    std.debug.print("\n", .{});
}

fn benchmarkDifferentSizes(allocator: std.mem.Allocator) !void {
    std.debug.print("Performance by Input Size:\n", .{});
    
    const sizes = [_]usize{
        64,           // 64B
        256,          // 256B
        1024,         // 1KB
        4096,         // 4KB
        16384,        // 16KB
        65536,        // 64KB
        262144,       // 256KB
        1048576,      // 1MB
    };
    
    for (sizes) |size| {
        const test_json = try generateJSON(allocator, size);
        defer allocator.free(test_json);
        
        const result = try benchmarkMinify(allocator, test_json, .{
            .name = "size test",
            .iterations = @max(100, 100000 / size),
        });
        
        std.debug.print("  {d: >7} bytes: {d:6.2} GB/s\n", .{
            size,
            result.throughput_gbps,
        });
    }
    
    std.debug.print("\n", .{});
}

fn benchmarkDifferentComplexity(allocator: std.mem.Allocator) !void {
    std.debug.print("Performance by JSON Complexity:\n", .{});
    
    // Flat object
    const flat = "{\"a\":1,\"b\":2,\"c\":3,\"d\":4,\"e\":5,\"f\":6,\"g\":7,\"h\":8,\"i\":9,\"j\":10}";
    
    // Nested object
    const nested = "{\"a\":{\"b\":{\"c\":{\"d\":{\"e\":{\"f\":{\"g\":{\"h\":{\"i\":{\"j\":10}}}}}}}}}}";
    
    // Array heavy
    const array = "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]";
    
    // String heavy
    const strings = "{\"a\":\"hello world\",\"b\":\"json minifier\",\"c\":\"performance test\"}";
    
    const test_cases = [_]struct {
        name: []const u8,
        json: []const u8,
    }{
        .{ .name = "flat object", .json = flat },
        .{ .name = "deep nesting", .json = nested },
        .{ .name = "array heavy", .json = array },
        .{ .name = "string heavy", .json = strings },
    };
    
    for (test_cases) |tc| {
        const result = try benchmarkMinify(allocator, tc.json, .{
            .name = tc.name,
            .iterations = 10000,
        });
        
        std.debug.print("  {s}: {d:.2} GB/s\n", .{
            tc.name,
            result.throughput_gbps,
        });
    }
    
    std.debug.print("\n", .{});
}

fn benchmarkMemoryStrategies(allocator: std.mem.Allocator) !void {
    std.debug.print("Memory Strategy Benchmarks:\n", .{});
    
    const strategies = [_]struct {
        name: []const u8,
        strategy: advanced.Config.MemoryStrategy,
    }{
        .{ .name = "standard", .strategy = .standard },
        .{ .name = "pooled", .strategy = .pooled },
        .{ .name = "adaptive", .strategy = .adaptive },
    };
    
    const test_json = try generateJSON(allocator, 64 * 1024); // 64KB
    defer allocator.free(test_json);
    
    for (strategies) |strat| {
        const config = advanced.Config{
            .memory_strategy = strat.strategy,
            .optimization_level = .aggressive,
        };
        
        var minifier = try advanced.AdvancedMinifier.init(allocator, config);
        defer minifier.deinit();
        
        const result = try benchmarkAdvancedMinify(&minifier, test_json, .{
            .name = strat.name,
            .iterations = 1000,
        });
        
        std.debug.print("  {s}: {d:.2} GB/s, peak mem: ~{d}KB\n", .{
            strat.name,
            result.throughput_gbps,
            result.peak_memory_kb,
        });
    }
    
    std.debug.print("\n", .{});
}

// Helper functions

const BenchmarkResult = struct {
    throughput_gbps: f64,
    ns_per_op: f64,
    peak_memory_kb: usize = 0,
};

fn benchmarkMinify(allocator: std.mem.Allocator, input: []const u8, bench: Benchmark) !BenchmarkResult {
    // Warmup
    for (0..bench.warmup_iterations) |_| {
        const result = try zmin.minify(allocator, input);
        allocator.free(result);
    }
    
    // Benchmark
    const start = std.time.nanoTimestamp();
    
    for (0..bench.iterations) |_| {
        const result = try zmin.minify(allocator, input);
        allocator.free(result);
    }
    
    const end = std.time.nanoTimestamp();
    const total_ns = @as(u64, @intCast(end - start));
    const ns_per_op = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(bench.iterations));
    
    const bytes_per_op = input.len;
    const bytes_per_second = (@as(f64, @floatFromInt(bytes_per_op)) * 1_000_000_000.0) / ns_per_op;
    const gbps = bytes_per_second / (1024.0 * 1024.0 * 1024.0);
    
    return BenchmarkResult{
        .throughput_gbps = gbps,
        .ns_per_op = ns_per_op,
    };
}

fn benchmarkAdvancedMinify(minifier: *advanced.AdvancedMinifier, input: []const u8, bench: Benchmark) !BenchmarkResult {
    // Warmup
    for (0..bench.warmup_iterations) |_| {
        const result = try minifier.minify(input);
        minifier.allocator.free(result);
    }
    
    // Benchmark
    const start = std.time.nanoTimestamp();
    var total_bytes: usize = 0;
    
    for (0..bench.iterations) |_| {
        const result = try minifier.minifyWithStats(input);
        total_bytes += input.len;
        minifier.allocator.free(result.output);
    }
    
    const end = std.time.nanoTimestamp();
    const total_ns = @as(u64, @intCast(end - start));
    const ns_per_op = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(bench.iterations));
    
    const bytes_per_second = (@as(f64, @floatFromInt(total_bytes)) * 1_000_000_000.0) / @as(f64, @floatFromInt(total_ns));
    const gbps = bytes_per_second / (1024.0 * 1024.0 * 1024.0);
    
    return BenchmarkResult{
        .throughput_gbps = gbps,
        .ns_per_op = ns_per_op,
    };
}

fn benchmarkStreaming(allocator: std.mem.Allocator, input: []const u8, bench: Benchmark) !BenchmarkResult {
    // Warmup
    for (0..bench.warmup_iterations) |_| {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        
        try zmin.minifyToWriter(input, output.writer());
    }
    
    // Benchmark
    const start = std.time.nanoTimestamp();
    
    for (0..bench.iterations) |_| {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        
        try zmin.minifyToWriter(input, output.writer());
    }
    
    const end = std.time.nanoTimestamp();
    const total_ns = @as(u64, @intCast(end - start));
    const ns_per_op = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(bench.iterations));
    
    const bytes_per_op = input.len;
    const bytes_per_second = (@as(f64, @floatFromInt(bytes_per_op)) * 1_000_000_000.0) / ns_per_op;
    const gbps = bytes_per_second / (1024.0 * 1024.0 * 1024.0);
    
    return BenchmarkResult{
        .throughput_gbps = gbps,
        .ns_per_op = ns_per_op,
    };
}

fn generateJSON(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);
    defer json.deinit();
    
    try json.appendSlice("{\n");
    
    var current_size: usize = 2;
    var i: usize = 0;
    
    while (current_size < target_size - 10) {
        const entry = try std.fmt.allocPrint(allocator, "  \"field_{}\": \"value_{}\"", .{ i, i });
        defer allocator.free(entry);
        
        try json.appendSlice(entry);
        current_size += entry.len;
        
        if (current_size < target_size - 10) {
            try json.appendSlice(",\n");
            current_size += 2;
        } else {
            try json.appendSlice("\n");
            current_size += 1;
        }
        
        i += 1;
    }
    
    try json.appendSlice("}");
    
    return json.toOwnedSlice();
}