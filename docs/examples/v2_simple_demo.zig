const std = @import("std");
const v2 = @import("zmin_lib").v2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== zmin v2.0 Streaming Parser Demo ===\n", .{});

    // Test JSON data
    const json_data = 
        \\{
        \\  "name": "zmin",
        \\  "version": "2.0",
        \\  "features": ["streaming", "SIMD", "parallel"],
        \\  "performance": {
        \\    "throughput": "10+ GB/s",
        \\    "optimizations": ["AVX-512", "NEON", "multi-threading"]
        \\  }
        \\}
    ;

    std.debug.print("\nInput JSON ({} bytes):\n{s}\n", .{ json_data.len, json_data });

    // Test single-threaded streaming parser
    {
        std.debug.print("\n--- Streaming Parser with SIMD ---\n", .{});
        
        var parser = try v2.StreamingParser.init(allocator, .{
            .enable_simd = true,
            .simd_level = .auto,
        });
        defer parser.deinit();

        const start_time = std.time.nanoTimestamp();
        var token_stream = try parser.parseStreaming(json_data);
        defer token_stream.deinit();
        const parse_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
        
        const token_count = token_stream.getTokenCount();
        std.debug.print("Tokens parsed: {}\n", .{token_count});
        std.debug.print("Parse time: {} μs\n", .{parse_time / 1000});
        std.debug.print("Throughput: {d:.2} MB/s\n", .{
            (@as(f64, @floatFromInt(json_data.len)) / @as(f64, @floatFromInt(parse_time))) * 1000.0,
        });
        
        // Print first few tokens
        std.debug.print("\nFirst 10 tokens:\n", .{});
        for (0..@min(10, token_count)) |i| {
            if (token_stream.getToken(i)) |token| {
                std.debug.print("  [{:2}] {s:15} @ {}-{}\n", .{
                    i,
                    @tagName(token.token_type),
                    token.start,
                    token.end,
                });
            }
        }
    }

    // Test transformation pipeline
    {
        std.debug.print("\n--- Transformation Pipeline ---\n", .{});
        
        var engine = try v2.ZminEngine.init(allocator, .{});
        defer engine.deinit();
        
        // Add minification transformation
        try engine.addTransformation(v2.Transformation.init(.{
            .minify = v2.MinifyConfig{
                .remove_whitespace = true,
                .aggressive = false,
            },
        }));
        
        const minified = try engine.processToString(allocator, json_data);
        defer allocator.free(minified);
        
        std.debug.print("Original size: {} bytes\n", .{json_data.len});
        std.debug.print("Minified size: {} bytes\n", .{minified.len});
        std.debug.print("Compression: {d:.1}%\n", .{
            (1.0 - @as(f64, @floatFromInt(minified.len)) / @as(f64, @floatFromInt(json_data.len))) * 100.0,
        });
        std.debug.print("Minified: {s}\n", .{minified});
    }

    // Benchmark with larger data
    {
        std.debug.print("\n--- Performance Benchmark ---\n", .{});
        
        // Generate larger JSON
        var json_buf = std.ArrayList(u8).init(allocator);
        defer json_buf.deinit();
        
        try json_buf.appendSlice("[\n");
        for (0..1000) |i| {
            if (i > 0) try json_buf.appendSlice(",\n");
            try json_buf.writer().print("  {{\"id\": {}, \"data\": \"item_{}\"}}", .{ i, i });
        }
        try json_buf.appendSlice("\n]");
        
        const large_json = json_buf.items;
        
        const result = try v2.benchmark(allocator, large_json, 100);
        result.print();
    }

    std.debug.print("\n=== Demo Complete ===\n", .{});
}