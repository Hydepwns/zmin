// Test advanced SIMD minifier implementations
const std = @import("std");
const AdvancedSIMDMinifier = @import("src/simd/avx_minifier_simple.zig").AdvancedSIMDMinifier;
const TurboMinifierAdaptive = @import("src/modes/turbo_minifier_adaptive.zig").TurboMinifierAdaptive;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n🚀 Advanced SIMD Minifier Test\n", .{});
    try stdout.print("==============================\n\n", .{});
    
    // Initialize SIMD minifier
    var simd_minifier = try AdvancedSIMDMinifier.init(allocator);
    defer simd_minifier.deinit();
    
    // Show detected SIMD capabilities
    const simd_info = simd_minifier.getSIMDInfo();
    try stdout.print("SIMD Detection:\n", .{});
    try stdout.print("  Level: {s}\n", .{simd_info.name});
    try stdout.print("  Vector Size: {d} bytes\n", .{simd_info.vector_size});
    try stdout.print("  AVX: {}\n", .{simd_info.features.avx});
    try stdout.print("  AVX2: {}\n", .{simd_info.features.avx2});
    try stdout.print("  AVX-512F: {}\n", .{simd_info.features.avx512f});
    try stdout.print("  AVX-VNNI: {}\n", .{simd_info.features.avx_vnni});
    try stdout.print("  BMI1/BMI2: {} / {}\n", .{ simd_info.features.bmi1, simd_info.features.bmi2 });
    try stdout.print("  POPCNT: {}\n\n", .{simd_info.features.popcnt});
    
    // Test different file sizes
    const test_sizes = [_]struct { size: usize, name: []const u8 }{
        .{ .size = 1024 * 1024, .name = "1 MB" },
        .{ .size = 10 * 1024 * 1024, .name = "10 MB" },
        .{ .size = 50 * 1024 * 1024, .name = "50 MB" },
        .{ .size = 100 * 1024 * 1024, .name = "100 MB" },
    };
    
    for (test_sizes) |test_case| {
        try stdout.print("🧪 Testing {s} file:\n", .{test_case.name});
        
        const input = try generateTestJson(allocator, test_case.size);
        defer allocator.free(input);
        
        const output_simd = try allocator.alloc(u8, input.len);
        defer allocator.free(output_simd);
        const output_adaptive = try allocator.alloc(u8, input.len);
        defer allocator.free(output_adaptive);
        
        // Test SIMD implementation
        const simd_start = std.time.nanoTimestamp();
        const simd_len = try simd_minifier.minify(input, output_simd);
        const simd_end = std.time.nanoTimestamp();
        const simd_ns = @as(u64, @intCast(simd_end - simd_start));
        const simd_ms = simd_ns / 1_000_000;
        const simd_throughput = if (simd_ms > 0)
            (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(simd_ms)) * 1000.0 / (1024.0 * 1024.0))
        else
            0.0;
        
        // Test adaptive implementation for comparison
        var adaptive = try TurboMinifierAdaptive.init(allocator, .{});
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
        
        const improvement = if (adaptive_throughput > 0)
            ((simd_throughput - adaptive_throughput) / adaptive_throughput * 100.0)
        else
            0.0;
        
        const match = (simd_len == adaptive_len);
        
        try stdout.print("  SIMD ({s}): {d:>7.1} MB/s ({d:>4} ms)\n", .{ simd_info.name, simd_throughput, simd_ms });
        try stdout.print("  Adaptive:      {d:>7.1} MB/s ({d:>4} ms)\n", .{ adaptive_throughput, adaptive_ms });
        try stdout.print("  Improvement:   {d:>7.1}% {s}\n", .{ improvement, if (match) "✅" else "❌" });
        
        // Calculate efficiency metrics
        const theoretical_max = calculateTheoreticalMax(simd_info.vector_size, test_case.size);
        const efficiency = if (theoretical_max > 0) (simd_throughput / theoretical_max * 100.0) else 0.0;
        
        try stdout.print("  Theoretical:   {d:>7.1} MB/s\n", .{theoretical_max});
        try stdout.print("  Efficiency:    {d:>7.1}%\n\n", .{efficiency});
    }
    
    // Test SIMD effectiveness on different content types
    try testContentTypes(allocator, &simd_minifier);
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
        
        const pattern = key_counter % 6;
        switch (pattern) {
            0 => try buffer.writer().print("  \"key_{d}\"   :   \"value with      many    spaces\"", .{key_counter}),
            1 => try buffer.writer().print("  \"data_{d}\"  : {{    \"num\"  :   {d}   ,   \"str\"  :  \"test\"    }}", .{key_counter, key_counter * 42}),
            2 => try buffer.writer().print("  \"array_{d}\" : [    1  ,   2   ,    3    ,     4     ]", .{key_counter}),
            3 => try buffer.writer().print("  \"nested_{d}\": {{   \"deep\" : {{    \"key\" :  \"value\"   }}   }}", .{key_counter}),
            4 => try buffer.writer().print("  \"whitespace_heavy_{d}\"    :     \"lots     of      spaces      here\"", .{key_counter}),
            5 => try buffer.writer().print("  \"tabs_and_newlines_{d}\" :\t\t \"value\t\twith\t\ttabs\" \n\n", .{key_counter}),
            else => unreachable,
        }
        
        key_counter += 1;
    }
    
    try buffer.appendSlice("\n}");
    return buffer.toOwnedSlice();
}

fn calculateTheoreticalMax(vector_size: usize, _: usize) f64 {
    // Theoretical maximum based on memory bandwidth and vector processing
    const base_throughput = 500.0; // MB/s base processing speed
    const vector_factor = @as(f64, @floatFromInt(vector_size)) / 16.0; // Scaling factor vs 16-byte baseline
    
    // Account for memory bandwidth limits
    const memory_bandwidth_limit = 18000.0; // 18 GB/s system memory
    const processing_limit = base_throughput * vector_factor;
    
    return @min(processing_limit, memory_bandwidth_limit);
}

fn testContentTypes(allocator: std.mem.Allocator, simd_minifier: *AdvancedSIMDMinifier) !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("📋 Content Type Analysis:\n", .{});
    try stdout.print("=========================\n", .{});
    
    const content_types = [_]struct { 
        content: []const u8, 
        name: []const u8 
    }{
        .{ 
            .content = "    {    \"high_whitespace\"    :    \"lots of spaces and tabs\"\t\t,\n\n    \"more\"   :   \"content\"    }", 
            .name = "High Whitespace" 
        },
        .{ 
            .content = "{\"compact\":\"minimal\",\"spaces\":false,\"efficient\":true}", 
            .name = "Already Compact" 
        },
        .{ 
            .content = "{\n  \"strings\": \"this has many string values that cannot be optimized much\",\n  \"content\": \"more string content here\"\n}", 
            .name = "String Heavy" 
        },
    };
    
    for (content_types) |test_case| {
        const output = try allocator.alloc(u8, test_case.content.len);
        defer allocator.free(output);
        
        const start = std.time.nanoTimestamp();
        const result_len = try simd_minifier.minify(test_case.content, output);
        const end = std.time.nanoTimestamp();
        
        const time_ns = @as(u64, @intCast(end - start));
        const reduction = (1.0 - @as(f64, @floatFromInt(result_len)) / @as(f64, @floatFromInt(test_case.content.len))) * 100.0;
        
        try stdout.print("  {s}:\n", .{test_case.name});
        try stdout.print("    Original: {d} bytes\n", .{test_case.content.len});
        try stdout.print("    Minified: {d} bytes\n", .{result_len});
        try stdout.print("    Reduction: {d:.1}%\n", .{reduction});
        try stdout.print("    Time: {d} μs\n\n", .{time_ns / 1000});
    }
}