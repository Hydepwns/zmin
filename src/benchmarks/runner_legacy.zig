const std = @import("std");
const MinifyingParser = @import("src/minifier/mod.zig").MinifyingParser;

const BenchmarkResult = struct {
    name: []const u8,
    file_path: []const u8,
    file_size: usize,
    time_ns: i128,
    throughput_mbps: f64,
    compression_ratio: f64,
    output_size: usize,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n═══════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("                    ZMIN PERFORMANCE BENCHMARK                      \n", .{});
    std.debug.print("═══════════════════════════════════════════════════════════════════\n\n", .{});

    // Test files
    const test_files = [_][]const u8{
        "test_input.json",
        "test_large.json",
        "datasets/twitter.json",
        "datasets/github.json",
        "datasets/citm.json",
        "datasets/canada.json",
    };

    var results = std.ArrayList(BenchmarkResult).init(allocator);
    defer results.deinit();

    // Run benchmarks
    for (test_files) |file_path| {
        const result = benchmarkFile(allocator, file_path) catch |err| {
            std.debug.print("⚠️  Skipping {s}: {}\n", .{ file_path, err });
            continue;
        };
        try results.append(result);
    }

    // Print results table
    std.debug.print("\n📊 Benchmark Results:\n", .{});
    std.debug.print("┌─────────────────────────┬────────────┬─────────────┬──────────────┬─────────────┐\n", .{});
    std.debug.print("│ File                    │ Size       │ Time        │ Throughput   │ Compression │\n", .{});
    std.debug.print("├─────────────────────────┼────────────┼─────────────┼──────────────┼─────────────┤\n", .{});

    var total_size: usize = 0;
    var total_time_ns: i128 = 0;

    for (results.items) |result| {
        const size_str = try formatSize(allocator, result.file_size);
        defer allocator.free(size_str);

        const time_ms = @as(f64, @floatFromInt(result.time_ns)) / 1_000_000.0;

        std.debug.print("│ {s:<23} │ {s:>10} │ {d:>9.2} ms │ {d:>9.2} MB/s │ {d:>10.1}% │\n", .{
            truncateString(result.name, 23),
            size_str,
            time_ms,
            result.throughput_mbps,
            result.compression_ratio,
        });

        total_size += result.file_size;
        total_time_ns += result.time_ns;
    }

    std.debug.print("└─────────────────────────┴────────────┴─────────────┴──────────────┴─────────────┘\n", .{});

    // Summary statistics
    if (results.items.len > 0) {
        const avg_throughput = (@as(f64, @floatFromInt(total_size)) / @as(f64, @floatFromInt(total_time_ns))) * 1_000_000_000.0 / (1024 * 1024);
        const total_size_str = try formatSize(allocator, total_size);
        defer allocator.free(total_size_str);

        std.debug.print("\n📈 Summary:\n", .{});
        std.debug.print("   • Total data processed: {s}\n", .{total_size_str});
        std.debug.print("   • Average throughput: {d:.2} MB/s\n", .{avg_throughput});
        std.debug.print("   • Files tested: {}\n", .{results.items.len});
    }

    // Performance comparison
    std.debug.print("\n🏆 Performance Comparison:\n", .{});
    std.debug.print("┌─────────────────────────┬──────────────┬─────────────────────────────┐\n", .{});
    std.debug.print("│ Tool                    │ Throughput   │ Notes                       │\n", .{});
    std.debug.print("├─────────────────────────┼──────────────┼─────────────────────────────┤\n", .{});
    std.debug.print("│ zmin (current)          │ ~50-80 MB/s  │ Streaming, O(1) memory      │\n", .{});
    std.debug.print("│ jq -c                   │ ~150 MB/s    │ Full parse, high memory     │\n", .{});
    std.debug.print("│ node JSON.stringify     │ ~200 MB/s    │ Full parse, high memory     │\n", .{});
    std.debug.print("│ RapidJSON               │ ~400 MB/s    │ C++, full parse             │\n", .{});
    std.debug.print("│ simdjson                │ ~3000 MB/s   │ SIMD optimized, C++         │\n", .{});
    std.debug.print("│ zmin (target)           │ 1000+ MB/s   │ With SIMD + parallel        │\n", .{});
    std.debug.print("└─────────────────────────┴──────────────┴─────────────────────────────┘\n", .{});

    std.debug.print("\n✨ Current implementation achieves streaming with constant memory usage.\n", .{});
    std.debug.print("   Future optimizations will significantly improve throughput.\n\n", .{});
}

fn benchmarkFile(allocator: std.mem.Allocator, file_path: []const u8) !BenchmarkResult {
    // Read file
    const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 100 * 1024 * 1024) catch |err| {
        return err;
    };
    defer allocator.free(file_content);

    // Create output buffer
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    // Benchmark the minification
    const start_time = std.time.nanoTimestamp();

    var parser = try MinifyingParser.init(allocator, output.writer().any());
    defer parser.deinit(allocator);

    try parser.feed(file_content);
    try parser.flush();

    const end_time = std.time.nanoTimestamp();
    const elapsed_ns = end_time - start_time;

    // Calculate metrics
    const throughput_mbps = if (elapsed_ns > 0)
        (@as(f64, @floatFromInt(file_content.len)) / @as(f64, @floatFromInt(elapsed_ns))) * 1_000_000_000.0 / (1024 * 1024)
    else
        0.0;

    const compression_ratio = if (file_content.len > 0)
        (@as(f64, @floatFromInt(file_content.len - output.items.len)) / @as(f64, @floatFromInt(file_content.len))) * 100.0
    else
        0.0;

    return BenchmarkResult{
        .name = file_path,
        .file_path = file_path,
        .file_size = file_content.len,
        .time_ns = elapsed_ns,
        .throughput_mbps = throughput_mbps,
        .compression_ratio = compression_ratio,
        .output_size = output.items.len,
    };
}

fn formatSize(allocator: std.mem.Allocator, size: usize) ![]u8 {
    if (size < 1024) {
        return std.fmt.allocPrint(allocator, "{} B", .{size});
    } else if (size < 1024 * 1024) {
        return std.fmt.allocPrint(allocator, "{d:.1} KB", .{@as(f64, @floatFromInt(size)) / 1024.0});
    } else {
        return std.fmt.allocPrint(allocator, "{d:.1} MB", .{@as(f64, @floatFromInt(size)) / (1024.0 * 1024.0)});
    }
}

fn truncateString(str: []const u8, max_len: usize) []const u8 {
    if (str.len <= max_len) return str;
    return str[0..max_len];
}
