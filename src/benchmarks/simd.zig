const std = @import("std");
const testing = std.testing;

// Import both regular and optimized versions
const types = @import("src/minifier/types.zig");
const optimized_types = @import("src/minifier/optimized_types.zig");
const MinifyingParser = types.MinifyingParser;
const OptimizedMinifyingParser = optimized_types.OptimizedMinifyingParser;

// Test data
const small_json = "{\"name\":\"John\",\"age\":30,\"city\":\"New York\"}";
const medium_json =
    \\{
    \\  "users": [
    \\    {"id": 1, "name": "Alice", "email": "alice@example.com", "active": true},
    \\    {"id": 2, "name": "Bob", "email": "bob@example.com", "active": false},
    \\    {"id": 3, "name": "Charlie", "email": "charlie@example.com", "active": true}
    \\  ],
    \\  "metadata": {
    \\    "version": "1.0.0",
    \\    "timestamp": "2024-01-01T00:00:00Z",
    \\    "count": 3
    \\  }
    \\}
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("JSON MINIFIER - SIMD OPTIMIZATION BENCHMARK\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});

    // Benchmark iterations
    const iterations = 10000;

    // Benchmark regular parser
    try benchmarkRegularParser(allocator, iterations);

    // Benchmark optimized parser
    try benchmarkOptimizedParser(allocator, iterations);

    // Large data benchmark
    try benchmarkLargeData(allocator);

    // Streaming benchmark
    try benchmarkStreaming(allocator);
}

fn benchmarkRegularParser(allocator: std.mem.Allocator, iterations: usize) !void {
    std.debug.print("🔷 Regular Parser Benchmark\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // Small JSON
    {
        var timer = try std.time.Timer.start();
        var total_bytes: u64 = 0;

        for (0..iterations) |_| {
            var output = std.ArrayList(u8).init(allocator);
            defer output.deinit();

            var parser = try MinifyingParser.init(allocator, output.writer().any());
            defer parser.deinit(allocator);

            try parser.feed(small_json);
            try parser.flush();

            total_bytes += small_json.len;
        }

        const elapsed_ns = timer.read();
        const elapsed_ms = elapsed_ns / 1_000_000;
        const throughput_mbps = if (elapsed_ms > 0) (total_bytes * 1000) / (elapsed_ms * 1024 * 1024) else 0;

        std.debug.print("Small JSON ({} bytes):\n", .{small_json.len});
        std.debug.print("  Time: {} ms\n", .{elapsed_ms});
        std.debug.print("  Throughput: {} MB/s\n", .{throughput_mbps});
        std.debug.print("  Per iteration: {} ns\n\n", .{elapsed_ns / iterations});
    }

    // Medium JSON
    {
        var timer = try std.time.Timer.start();
        var total_bytes: u64 = 0;

        for (0..iterations) |_| {
            var output = std.ArrayList(u8).init(allocator);
            defer output.deinit();

            var parser = try MinifyingParser.init(allocator, output.writer().any());
            defer parser.deinit(allocator);

            try parser.feed(medium_json);
            try parser.flush();

            total_bytes += medium_json.len;
        }

        const elapsed_ns = timer.read();
        const elapsed_ms = elapsed_ns / 1_000_000;
        const throughput_mbps = if (elapsed_ms > 0) (total_bytes * 1000) / (elapsed_ms * 1024 * 1024) else 0;

        std.debug.print("Medium JSON ({} bytes):\n", .{medium_json.len});
        std.debug.print("  Time: {} ms\n", .{elapsed_ms});
        std.debug.print("  Throughput: {} MB/s\n", .{throughput_mbps});
        std.debug.print("  Per iteration: {} ns\n\n", .{elapsed_ns / iterations});
    }
}

fn benchmarkOptimizedParser(allocator: std.mem.Allocator, iterations: usize) !void {
    std.debug.print("⚡ Optimized Parser Benchmark (SIMD)\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // Small JSON
    {
        var timer = try std.time.Timer.start();
        var total_bytes: u64 = 0;

        for (0..iterations) |_| {
            var output = std.ArrayList(u8).init(allocator);
            defer output.deinit();

            var parser = try OptimizedMinifyingParser.init(allocator, output.writer().any());
            defer parser.deinit(allocator);

            try parser.feedOptimized(small_json);
            try parser.flush();

            total_bytes += small_json.len;
        }

        const elapsed_ns = timer.read();
        const elapsed_ms = elapsed_ns / 1_000_000;
        const throughput_mbps = if (elapsed_ms > 0) (total_bytes * 1000) / (elapsed_ms * 1024 * 1024) else 0;

        std.debug.print("Small JSON ({} bytes):\n", .{small_json.len});
        std.debug.print("  Time: {} ms\n", .{elapsed_ms});
        std.debug.print("  Throughput: {} MB/s\n", .{throughput_mbps});
        std.debug.print("  Per iteration: {} ns\n\n", .{elapsed_ns / iterations});
    }

    // Medium JSON
    {
        var timer = try std.time.Timer.start();
        var total_bytes: u64 = 0;

        for (0..iterations) |_| {
            var output = std.ArrayList(u8).init(allocator);
            defer output.deinit();

            var parser = try OptimizedMinifyingParser.init(allocator, output.writer().any());
            defer parser.deinit(allocator);

            try parser.feedOptimized(medium_json);
            try parser.flush();

            total_bytes += medium_json.len;
        }

        const elapsed_ns = timer.read();
        const elapsed_ms = elapsed_ns / 1_000_000;
        const throughput_mbps = if (elapsed_ms > 0) (total_bytes * 1000) / (elapsed_ms * 1024 * 1024) else 0;

        std.debug.print("Medium JSON ({} bytes):\n", .{medium_json.len});
        std.debug.print("  Time: {} ms\n", .{elapsed_ms});
        std.debug.print("  Throughput: {} MB/s\n", .{throughput_mbps});
        std.debug.print("  Per iteration: {} ns\n\n", .{elapsed_ns / iterations});
    }
}

fn benchmarkLargeData(allocator: std.mem.Allocator) !void {
    std.debug.print("📊 Large Data Benchmark\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    // Generate large JSON array
    var large_json = std.ArrayList(u8).init(allocator);
    defer large_json.deinit();

    try large_json.append('[');
    for (0..10000) |i| {
        if (i > 0) try large_json.appendSlice(",");
        const item = try std.fmt.allocPrint(allocator, "{{\"id\":{},\"value\":{},\"active\":{}}}", .{ i, i * 2, i % 2 == 0 });
        defer allocator.free(item);
        try large_json.appendSlice(item);
    }
    try large_json.append(']');

    // Regular parser
    {
        var timer = try std.time.Timer.start();

        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(allocator, output.writer().any());
        defer parser.deinit(allocator);

        try parser.feed(large_json.items);
        try parser.flush();

        const elapsed_ns = timer.read();
        const elapsed_ms = elapsed_ns / 1_000_000;
        const throughput_mbps = if (elapsed_ms > 0) (large_json.items.len * 1000) / (elapsed_ms * 1024 * 1024) else 0;

        std.debug.print("Regular Parser - {} KB:\n", .{large_json.items.len / 1024});
        std.debug.print("  Time: {} ms\n", .{elapsed_ms});
        std.debug.print("  Throughput: {} MB/s\n\n", .{throughput_mbps});
    }

    // Optimized parser
    {
        var timer = try std.time.Timer.start();

        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        var parser = try OptimizedMinifyingParser.init(allocator, output.writer().any());
        defer parser.deinit(allocator);

        try parser.feedOptimized(large_json.items);
        try parser.flush();

        const elapsed_ns = timer.read();
        const elapsed_ms = elapsed_ns / 1_000_000;
        const throughput_mbps = if (elapsed_ms > 0) (large_json.items.len * 1000) / (elapsed_ms * 1024 * 1024) else 0;

        std.debug.print("Optimized Parser - {} KB:\n", .{large_json.items.len / 1024});
        std.debug.print("  Time: {} ms\n", .{elapsed_ms});
        std.debug.print("  Throughput: {} MB/s\n\n", .{throughput_mbps});
    }
}

fn benchmarkStreaming(allocator: std.mem.Allocator) !void {
    std.debug.print("🌊 Streaming Performance\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const chunk_sizes = [_]usize{ 64, 256, 1024, 4096, 16384 };

    // Generate test data
    var test_data = std.ArrayList(u8).init(allocator);
    defer test_data.deinit();

    try test_data.appendSlice("{\"data\":[");
    for (0..1000) |i| {
        if (i > 0) try test_data.append(',');
        try test_data.appendSlice("\"");
        for (0..100) |_| {
            try test_data.append('x');
        }
        try test_data.appendSlice("\"");
    }
    try test_data.appendSlice("]}");

    std.debug.print("Test data size: {} KB\n\n", .{test_data.items.len / 1024});

    for (chunk_sizes) |chunk_size| {
        // Regular parser
        {
            var timer = try std.time.Timer.start();

            var output = std.ArrayList(u8).init(allocator);
            defer output.deinit();

            var parser = try MinifyingParser.init(allocator, output.writer().any());
            defer parser.deinit(allocator);

            var pos: usize = 0;
            while (pos < test_data.items.len) {
                const end = @min(pos + chunk_size, test_data.items.len);
                try parser.feed(test_data.items[pos..end]);
                pos = end;
            }
            try parser.flush();

            const elapsed_us = timer.read() / 1000;
            std.debug.print("Regular - Chunk {} bytes: {} µs\n", .{ chunk_size, elapsed_us });
        }

        // Optimized parser
        {
            var timer = try std.time.Timer.start();

            var output = std.ArrayList(u8).init(allocator);
            defer output.deinit();

            var parser = try OptimizedMinifyingParser.init(allocator, output.writer().any());
            defer parser.deinit(allocator);

            var pos: usize = 0;
            while (pos < test_data.items.len) {
                const end = @min(pos + chunk_size, test_data.items.len);
                try parser.feedOptimized(test_data.items[pos..end]);
                pos = end;
            }
            try parser.flush();

            const elapsed_us = timer.read() / 1000;
            std.debug.print("Optimized - Chunk {} bytes: {} µs\n\n", .{ chunk_size, elapsed_us });
        }
    }

    std.debug.print("\n✨ SIMD Optimization Results Summary:\n", .{});
    std.debug.print("The optimized parser should show significant improvements,\n", .{});
    std.debug.print("especially for larger data and optimal chunk sizes.\n", .{});
    std.debug.print("============================================================\n", .{});
}
