//! zmin v2.0 Performance Baseline Benchmark
//!
//! This benchmark establishes the performance baseline for the v2.0 streaming engine
//! character-based minifier. It tests various input sizes and measures throughput.
//!
//! The results from this benchmark are used to track performance improvements
//! as SIMD and parallel optimizations are implemented.
//!
//! Usage: cd to project root, then: zig run tests/benchmarks/v2_performance_baseline.zig -I src

const std = @import("std");
const char_minifier = @import("v2/char_minifier.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== zmin v2.0 Performance Baseline Test ===\n", .{});
    
    // Test data of varying sizes
    const test_cases = [_]struct {
        name: []const u8,
        json: []const u8,
    }{
        .{
            .name = "Small JSON",
            .json = "{\"name\":\"test\",\"value\":42,\"active\":true}",
        },
        .{
            .name = "Medium JSON",
            .json = 
                \\{
                \\  "users": [
                \\    {"id": 1, "name": "Alice", "email": "alice@example.com", "active": true},
                \\    {"id": 2, "name": "Bob", "email": "bob@example.com", "active": false},
                \\    {"id": 3, "name": "Charlie", "email": "charlie@example.com", "active": true}
                \\  ],
                \\  "metadata": {
                \\    "version": "1.0",
                \\    "timestamp": "2024-01-01T00:00:00Z",
                \\    "total": 3
                \\  }
                \\}
            ,
        },
        .{
            .name = "Large JSON",
            .json = generate_large_json(allocator) catch |err| {
                std.debug.print("Error generating large JSON: {}\n", .{err});
                return;
            },
        },
    };
    
    const iterations = 10000;
    
    for (test_cases) |test_case| {
        std.debug.print("\n--- {s} ---\n", .{test_case.name});
        std.debug.print("Input size: {d} bytes\n", .{test_case.json.len});
        
        // Test standard minification
        {
            const start_time = std.time.nanoTimestamp();
            
            var total_output_size: usize = 0;
            for (0..iterations) |_| {
                const output = try char_minifier.minifyCharBased(allocator, test_case.json);
                total_output_size += output.len;
                allocator.free(output);
            }
            
            const end_time = std.time.nanoTimestamp();
            const elapsed_ns = @as(u64, @intCast(end_time - start_time));
            const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
            
            const avg_output_size = total_output_size / iterations;
            const throughput_mb_s = (@as(f64, @floatFromInt(test_case.json.len * iterations)) / (1024.0 * 1024.0)) / (elapsed_ms / 1000.0);
            
            std.debug.print("Standard Minification:\n", .{});
            std.debug.print("  Time: {d:.2} ms ({d} iterations)\n", .{ elapsed_ms, iterations });
            std.debug.print("  Output size: {d} bytes ({d:.1}% of original)\n", .{ 
                avg_output_size, 
                @as(f64, @floatFromInt(avg_output_size)) / @as(f64, @floatFromInt(test_case.json.len)) * 100.0 
            });
            std.debug.print("  Throughput: {d:.1} MB/s\n", .{throughput_mb_s});
        }
        
        // Test aggressive minification
        {
            const start_time = std.time.nanoTimestamp();
            
            var total_output_size: usize = 0;
            for (0..iterations) |_| {
                const output = try char_minifier.minifyAggressiveCharBased(allocator, test_case.json);
                total_output_size += output.len;
                allocator.free(output);
            }
            
            const end_time = std.time.nanoTimestamp();
            const elapsed_ns = @as(u64, @intCast(end_time - start_time));
            const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
            
            const avg_output_size = total_output_size / iterations;
            const throughput_mb_s = (@as(f64, @floatFromInt(test_case.json.len * iterations)) / (1024.0 * 1024.0)) / (elapsed_ms / 1000.0);
            
            std.debug.print("Aggressive Minification:\n", .{});
            std.debug.print("  Time: {d:.2} ms ({d} iterations)\n", .{ elapsed_ms, iterations });
            std.debug.print("  Output size: {d} bytes ({d:.1}% of original)\n", .{ 
                avg_output_size, 
                @as(f64, @floatFromInt(avg_output_size)) / @as(f64, @floatFromInt(test_case.json.len)) * 100.0 
            });
            std.debug.print("  Throughput: {d:.1} MB/s\n", .{throughput_mb_s});
        }
    }
    
    // Free the large JSON if we allocated it
    if (test_cases[2].json.ptr != test_cases[1].json.ptr) {
        allocator.free(test_cases[2].json);
    }
    
    std.debug.print("\n=== Performance Test Complete ===\n", .{});
}

fn generate_large_json(allocator: std.mem.Allocator) ![]const u8 {
    var json = std.ArrayList(u8).init(allocator);
    defer json.deinit();
    
    try json.appendSlice("{\n  \"data\": [\n");
    
    const count = 1000;
    for (0..count) |i| {
        if (i > 0) try json.appendSlice(",\n");
        
        try json.writer().print(
            \\    {{
            \\      "id": {},
            \\      "name": "Item {}",
            \\      "value": {d:.2},
            \\      "active": {},
            \\      "tags": ["tag1", "tag2", "tag3"],
            \\      "metadata": {{
            \\        "created": "2024-01-{:0>2}T00:00:00Z",
            \\        "priority": {}
            \\      }}
            \\    }}
        , .{ 
            i, 
            i, 
            @as(f64, @floatFromInt(i)) * 1.23, 
            i % 2 == 0, 
            (i % 28) + 1, 
            i % 10 
        });
    }
    
    try json.appendSlice("\n  ],\n  \"total\": ");
    try json.writer().print("{}", .{count});
    try json.appendSlice("\n}");
    
    return json.toOwnedSlice();
}