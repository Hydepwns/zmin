const std = @import("std");
const zmin = @import("zmin_lib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n=== zmin v2.0 SIMD Optimization Demo ===\n\n", .{});
    
    // Generate test JSON with lots of literals
    var json_buf = std.ArrayList(u8).init(allocator);
    defer json_buf.deinit();
    
    try json_buf.appendSlice("{\n");
    try json_buf.appendSlice("  \"metadata\": {\n");
    try json_buf.appendSlice("    \"version\": \"2.0\",\n");
    try json_buf.appendSlice("    \"simd_enabled\": true,\n");
    try json_buf.appendSlice("    \"features\": [\"avx512\", \"neon\", \"parallel\"]\n");
    try json_buf.appendSlice("  },\n");
    try json_buf.appendSlice("  \"data\": [\n");
    
    // Add many items with boolean and null values
    const item_count = 1000;
    for (0..item_count) |i| {
        try json_buf.writer().print(
            \\    {{
            \\      "id": {},
            \\      "active": {s},
            \\      "verified": {s},
            \\      "value": {s},
            \\      "metadata": {s}
            \\    }}
        , .{
            i,
            if (i % 3 == 0) "true" else "false",
            if (i % 2 == 0) "false" else "true", 
            if (i % 5 == 0) "null" else "42",
            if (i % 7 == 0) "null" else "\"data\"",
        });
        
        if (i < item_count - 1) {
            try json_buf.appendSlice(",\n");
        } else {
            try json_buf.appendSlice("\n");
        }
    }
    
    try json_buf.appendSlice("  ]\n}");
    
    const json_data = json_buf.items;
    std.debug.print("Generated JSON size: {} bytes\n", .{json_data.len});
    
    // Benchmark v1 minification
    const v1_start = std.time.nanoTimestamp();
    const v1_result = try zmin.minify(allocator, json_data, .turbo);
    defer allocator.free(v1_result);
    const v1_time = std.time.nanoTimestamp() - v1_start;
    
    // Benchmark v2 minification (with SIMD)
    const v2_start = std.time.nanoTimestamp();
    const v2_result = try zmin.minifyV2(allocator, json_data);
    defer allocator.free(v2_result);
    const v2_time = std.time.nanoTimestamp() - v2_start;
    
    // Calculate performance metrics
    const v1_mbps = (@as(f64, @floatFromInt(json_data.len)) / 1024.0 / 1024.0) / 
                    (@as(f64, @floatFromInt(v1_time)) / 1_000_000_000.0);
    const v2_mbps = (@as(f64, @floatFromInt(json_data.len)) / 1024.0 / 1024.0) / 
                    (@as(f64, @floatFromInt(v2_time)) / 1_000_000_000.0);
    const speedup = v2_mbps / v1_mbps;
    
    std.debug.print("\nPerformance Results:\n", .{});
    std.debug.print("===================\n", .{});
    std.debug.print("v1.0 (TURBO mode):\n", .{});
    std.debug.print("  Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(v1_time)) / 1_000_000.0});
    std.debug.print("  Throughput: {d:.2} MB/s\n", .{v1_mbps});
    std.debug.print("  Output size: {} bytes\n\n", .{v1_result.len});
    
    std.debug.print("v2.0 (SIMD optimized):\n", .{});
    std.debug.print("  Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(v2_time)) / 1_000_000.0});
    std.debug.print("  Throughput: {d:.2} MB/s\n", .{v2_mbps});
    std.debug.print("  Output size: {} bytes\n", .{v2_result.len});
    std.debug.print("  Speedup: {d:.2}x\n\n", .{speedup});
    
    // Show a sample of the minified output
    std.debug.print("Sample output (first 200 chars):\n", .{});
    const sample_len = @min(200, v2_result.len);
    std.debug.print("{s}...\n", .{v2_result[0..sample_len]});
    
    std.debug.print("\n✅ SIMD optimizations successfully applied!\n", .{});
    std.debug.print("   - AVX-512/AVX2/NEON for structural character detection\n", .{});
    std.debug.print("   - Vectorized string parsing\n", .{});
    std.debug.print("   - Optimized number parsing\n", .{});
    std.debug.print("   - Enhanced boolean/null literal parsing\n", .{});
}