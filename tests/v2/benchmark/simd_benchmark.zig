const std = @import("std");
const testing = std.testing;
const StreamingParser = @import("../../../src/v2/streaming/parser.zig").StreamingParser;
const ParserConfig = @import("../../../src/v2/streaming/parser.zig").ParserConfig;
const SimdLevel = @import("../../../src/v2/streaming/parser.zig").SimdLevel;

test "V2 SIMD performance benchmark" {
    const allocator = testing.allocator;
    
    // Generate test data
    const sizes = [_]usize{ 1024, 10 * 1024, 100 * 1024 };
    
    std.debug.print("\n=== V2.0 SIMD JSON Parser Performance ===\n", .{});
    
    for (sizes) |size| {
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();
        
        try buf.appendSlice("{\n");
        const items = size / 100;
        for (0..items) |i| {
            try buf.writer().print("  \"item_{}\": {}, \"flag_{}\": {}\n", .{
                i,
                if (i % 3 == 0) "true" else if (i % 3 == 1) "false" else "null",
                i,
                if (i % 2 == 0) "true" else "false",
            });
            if (i < items - 1) try buf.appendSlice(",");
        }
        try buf.appendSlice("}");
        
        const data = buf.items;
        
        // Benchmark scalar
        var scalar_parser = try StreamingParser.init(allocator, .{
            .enable_simd = false,
            .simd_level = .none,
        });
        defer scalar_parser.deinit();
        
        const scalar_start = std.time.nanoTimestamp();
        var scalar_stream = try scalar_parser.parseStreaming(data);
        defer scalar_stream.deinit();
        
        var scalar_tokens: usize = 0;
        while (scalar_stream.hasMore()) {
            if (scalar_stream.getCurrentToken()) |_| {
                scalar_tokens += 1;
            }
            scalar_stream.advance();
        }
        const scalar_time = std.time.nanoTimestamp() - scalar_start;
        
        // Benchmark SIMD
        var simd_parser = try StreamingParser.init(allocator, .{
            .enable_simd = true,
            .simd_level = .auto,
        });
        defer simd_parser.deinit();
        
        const simd_start = std.time.nanoTimestamp();
        var simd_stream = try simd_parser.parseStreaming(data);
        defer simd_stream.deinit();
        
        var simd_tokens: usize = 0;
        while (simd_stream.hasMore()) {
            if (simd_stream.getCurrentToken()) |_| {
                simd_tokens += 1;
            }
            simd_stream.advance();
        }
        const simd_time = std.time.nanoTimestamp() - simd_start;
        
        // Calculate results
        const scalar_mbps = (@as(f64, @floatFromInt(data.len)) / 1024.0 / 1024.0) / 
                           (@as(f64, @floatFromInt(scalar_time)) / 1_000_000_000.0);
        const simd_mbps = (@as(f64, @floatFromInt(data.len)) / 1024.0 / 1024.0) / 
                          (@as(f64, @floatFromInt(simd_time)) / 1_000_000_000.0);
        const speedup = simd_mbps / scalar_mbps;
        
        std.debug.print("\nSize: {} KB\n", .{size / 1024});
        std.debug.print("  Scalar: {d:.2} MB/s ({} tokens)\n", .{ scalar_mbps, scalar_tokens });
        std.debug.print("  SIMD:   {d:.2} MB/s ({} tokens)\n", .{ simd_mbps, simd_tokens });
        std.debug.print("  Speedup: {d:.2}x\n", .{speedup});
        
        try testing.expectEqual(scalar_tokens, simd_tokens);
    }
}