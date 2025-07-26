//! Comprehensive Performance Benchmark Suite
//!
//! This module provides automated performance testing, validation, and
//! regression detection for the zmin JSON minifier.

const std = @import("std");
const zmin = @import("zmin_lib");

/// Benchmark configuration
pub const BenchmarkConfig = struct {
    /// Number of iterations per test
    iterations: u32 = 5,
    /// Warmup iterations before measurement
    warmup_iterations: u32 = 2,
    /// Dataset sizes to test
    dataset_sizes: []const DatasetSize = &.{ .small, .medium, .large, .xlarge },
    /// Modes to benchmark
    modes: []const zmin.ProcessingMode = &.{ .eco, .sport, .turbo },
    /// Output format
    output_format: OutputFormat = .markdown,
    /// Performance thresholds (MB/s)
    thresholds: PerformanceThresholds = .{},
};

/// Dataset size categories
pub const DatasetSize = enum {
    tiny,    // < 1KB
    small,   // 1KB - 100KB
    medium,  // 100KB - 10MB
    large,   // 10MB - 100MB
    xlarge,  // > 100MB
    
    pub fn getDescription(self: DatasetSize) []const u8 {
        return switch (self) {
            .tiny => "< 1KB",
            .small => "1KB - 100KB",
            .medium => "100KB - 10MB",
            .large => "10MB - 100MB",
            .xlarge => "> 100MB",
        };
    }
    
    pub fn getTargetSize(self: DatasetSize) usize {
        return switch (self) {
            .tiny => 512,
            .small => 50 * 1024,
            .medium => 5 * 1024 * 1024,
            .large => 50 * 1024 * 1024,
            .xlarge => 200 * 1024 * 1024,
        };
    }
};

/// Performance thresholds for regression detection
pub const PerformanceThresholds = struct {
    eco_min_mbps: f64 = 400.0,
    sport_min_mbps: f64 = 600.0,
    turbo_min_mbps: f64 = 1500.0,
    regression_tolerance: f64 = 0.95, // 5% tolerance
};

/// Output format options
pub const OutputFormat = enum {
    json,
    csv,
    markdown,
    human,
};

/// Benchmark result for a single test
pub const BenchmarkResult = struct {
    mode: zmin.ProcessingMode,
    dataset_size: DatasetSize,
    input_bytes: u64,
    output_bytes: u64,
    compression_ratio: f64,
    iterations: u32,
    
    // Timing statistics (microseconds)
    min_time_us: u64,
    max_time_us: u64,
    avg_time_us: u64,
    median_time_us: u64,
    stddev_time_us: f64,
    
    // Throughput statistics (MB/s)
    min_throughput_mbps: f64,
    max_throughput_mbps: f64,
    avg_throughput_mbps: f64,
    
    // Memory statistics
    peak_memory_bytes: u64,
    
    // System info
    cpu_cores: u32,
    numa_nodes: u32,
    
    /// Check if result meets performance thresholds
    pub fn meetsThreshold(self: BenchmarkResult, thresholds: PerformanceThresholds) bool {
        const min_expected = switch (self.mode) {
            .eco => thresholds.eco_min_mbps,
            .sport => thresholds.sport_min_mbps,
            .turbo => thresholds.turbo_min_mbps,
        };
        
        return self.avg_throughput_mbps >= min_expected * thresholds.regression_tolerance;
    }
};

/// Complete benchmark suite results
pub const BenchmarkSuite = struct {
    results: std.ArrayList(BenchmarkResult),
    start_time: i64,
    end_time: i64,
    system_info: SystemInfo,
    config: BenchmarkConfig,
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, config: BenchmarkConfig) !BenchmarkSuite {
        return BenchmarkSuite{
            .results = std.ArrayList(BenchmarkResult).init(allocator),
            .start_time = std.time.timestamp(),
            .end_time = 0,
            .system_info = try SystemInfo.detect(allocator),
            .config = config,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *BenchmarkSuite) void {
        self.results.deinit();
        self.system_info.deinit();
    }
    
    /// Add a benchmark result
    pub fn addResult(self: *BenchmarkSuite, result: BenchmarkResult) !void {
        try self.results.append(result);
    }
    
    /// Finalize the benchmark suite
    pub fn finalize(self: *BenchmarkSuite) void {
        self.end_time = std.time.timestamp();
    }
    
    /// Generate report in specified format
    pub fn generateReport(self: *BenchmarkSuite, writer: anytype) !void {
        switch (self.config.output_format) {
            .markdown => try self.generateMarkdownReport(writer),
            .json => try self.generateJsonReport(writer),
            .csv => try self.generateCsvReport(writer),
            .human => try self.generateHumanReport(writer),
        }
    }
    
    fn generateMarkdownReport(self: *BenchmarkSuite, writer: anytype) !void {
        try writer.print("# Zmin Performance Benchmark Report\n\n", .{});
        try writer.print("**Date**: {d}\n", .{self.start_time});
        try writer.print("**Duration**: {d}s\n", .{self.end_time - self.start_time});
        try writer.print("**System**: {s} ({d} cores, {d} NUMA nodes)\n\n", .{
            self.system_info.os_name,
            self.system_info.cpu_cores,
            self.system_info.numa_nodes,
        });
        
        // Summary table
        try writer.print("## Performance Summary\n\n", .{});
        try writer.print("| Mode | Dataset | Size (MB) | Throughput (MB/s) | Compression | Status |\n", .{});
        try writer.print("|------|---------|-----------|-------------------|-------------|--------|\n", .{});
        
        for (self.results.items) |result| {
            const status = if (result.meetsThreshold(self.config.thresholds)) "✅ PASS" else "❌ FAIL";
            const size_mb = @as(f64, @floatFromInt(result.input_bytes)) / (1024.0 * 1024.0);
            
            try writer.print("| {s} | {s} | {d:.2} | {d:.2} | {d:.1}% | {s} |\n", .{
                @tagName(result.mode),
                @tagName(result.dataset_size),
                size_mb,
                result.avg_throughput_mbps,
                result.compression_ratio * 100.0,
                status,
            });
        }
        
        // Detailed results
        try writer.print("\n## Detailed Results\n\n", .{});
        for (self.results.items) |result| {
            try writer.print("### {s} Mode - {s} Dataset\n", .{
                @tagName(result.mode),
                result.dataset_size.getDescription(),
            });
            try writer.print("- **Input Size**: {d} bytes\n", .{result.input_bytes});
            try writer.print("- **Output Size**: {d} bytes ({d:.1}% reduction)\n", .{
                result.output_bytes,
                result.compression_ratio * 100.0,
            });
            try writer.print("- **Throughput**: {d:.2} MB/s (min: {d:.2}, max: {d:.2})\n", .{
                result.avg_throughput_mbps,
                result.min_throughput_mbps,
                result.max_throughput_mbps,
            });
            try writer.print("- **Latency**: {d} µs (σ = {d:.2})\n", .{
                result.avg_time_us,
                result.stddev_time_us,
            });
            try writer.print("- **Peak Memory**: {d:.2} MB\n\n", .{
                @as(f64, @floatFromInt(result.peak_memory_bytes)) / (1024.0 * 1024.0),
            });
        }
    }
    
    fn generateJsonReport(self: *BenchmarkSuite, writer: anytype) !void {
        // TODO: Implement JSON report generation
        _ = self;
        _ = writer;
    }
    
    fn generateCsvReport(self: *BenchmarkSuite, writer: anytype) !void {
        // CSV header
        try writer.print("mode,dataset_size,input_bytes,output_bytes,compression_ratio,", .{});
        try writer.print("avg_throughput_mbps,min_throughput_mbps,max_throughput_mbps,", .{});
        try writer.print("avg_time_us,stddev_time_us,peak_memory_bytes,status\n", .{});
        
        // Data rows
        for (self.results.items) |result| {
            const status = if (result.meetsThreshold(self.config.thresholds)) "PASS" else "FAIL";
            try writer.print("{s},{s},{d},{d},{d:.4},{d:.2},{d:.2},{d:.2},{d},{d:.2},{d},{s}\n", .{
                @tagName(result.mode),
                @tagName(result.dataset_size),
                result.input_bytes,
                result.output_bytes,
                result.compression_ratio,
                result.avg_throughput_mbps,
                result.min_throughput_mbps,
                result.max_throughput_mbps,
                result.avg_time_us,
                result.stddev_time_us,
                result.peak_memory_bytes,
                status,
            });
        }
    }
    
    fn generateHumanReport(self: *BenchmarkSuite, writer: anytype) !void {
        try writer.print("\n🚀 Zmin Performance Benchmark Results\n", .{});
        try writer.print("{'='<|50}\n\n", .{});
        
        var passed: u32 = 0;
        var failed: u32 = 0;
        
        for (self.results.items) |result| {
            if (result.meetsThreshold(self.config.thresholds)) {
                passed += 1;
            } else {
                failed += 1;
            }
        }
        
        try writer.print("✅ Passed: {d}/{d}\n", .{ passed, passed + failed });
        if (failed > 0) {
            try writer.print("❌ Failed: {d}/{d}\n", .{ failed, passed + failed });
        }
        
        try writer.print("\nTop Performance:\n", .{});
        
        // Find best results for each mode
        for (self.config.modes) |mode| {
            var best_throughput: f64 = 0;
            var best_dataset: ?DatasetSize = null;
            
            for (self.results.items) |result| {
                if (result.mode == mode and result.avg_throughput_mbps > best_throughput) {
                    best_throughput = result.avg_throughput_mbps;
                    best_dataset = result.dataset_size;
                }
            }
            
            if (best_dataset) |dataset| {
                try writer.print("  {s}: {d:.2} MB/s on {s} dataset\n", .{
                    @tagName(mode),
                    best_throughput,
                    @tagName(dataset),
                });
            }
        }
    }
};

/// System information for benchmark context
pub const SystemInfo = struct {
    os_name: []const u8,
    cpu_model: []const u8,
    cpu_cores: u32,
    numa_nodes: u32,
    total_memory: u64,
    zig_version: []const u8,
    
    allocator: std.mem.Allocator,
    
    pub fn detect(allocator: std.mem.Allocator) !SystemInfo {
        const numa_detector = @import("../../src/performance/numa_detector.zig");
        const topology = try numa_detector.detect(allocator);
        defer topology.deinit();
        
        return SystemInfo{
            .os_name = try std.fmt.allocPrint(allocator, "{s}", .{@tagName(std.builtin.os.tag)}),
            .cpu_model = try allocator.dupe(u8, "Unknown"), // TODO: Detect CPU model
            .cpu_cores = std.Thread.getCpuCount() catch 1,
            .numa_nodes = topology.node_count,
            .total_memory = topology.total_memory,
            .zig_version = @import("builtin").zig_version_string,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *SystemInfo) void {
        self.allocator.free(self.os_name);
        self.allocator.free(self.cpu_model);
    }
};

/// Run comprehensive benchmark suite
pub fn runBenchmarkSuite(allocator: std.mem.Allocator, config: BenchmarkConfig) !BenchmarkSuite {
    var suite = try BenchmarkSuite.init(allocator, config);
    errdefer suite.deinit();
    
    std.debug.print("Starting comprehensive benchmark suite...\n", .{});
    
    // Generate test datasets
    for (config.dataset_sizes) |size| {
        const dataset = try generateDataset(allocator, size);
        defer allocator.free(dataset);
        
        std.debug.print("Testing {s} dataset ({d} bytes)...\n", .{
            size.getDescription(),
            dataset.len,
        });
        
        // Test each mode
        for (config.modes) |mode| {
            const result = try benchmarkMode(allocator, mode, dataset, config);
            try suite.addResult(result);
            
            std.debug.print("  {s} mode: {d:.2} MB/s\n", .{
                @tagName(mode),
                result.avg_throughput_mbps,
            });
        }
    }
    
    suite.finalize();
    return suite;
}

/// Benchmark a specific mode with dataset
fn benchmarkMode(
    allocator: std.mem.Allocator,
    mode: zmin.ProcessingMode,
    dataset: []const u8,
    config: BenchmarkConfig,
) !BenchmarkResult {
    var times = try allocator.alloc(u64, config.iterations);
    defer allocator.free(times);
    
    var peak_memory: u64 = 0;
    var output_size: u64 = 0;
    
    // Warmup iterations
    for (0..config.warmup_iterations) |_| {
        const output = try zmin.minifyWithMode(allocator, dataset, mode);
        allocator.free(output);
    }
    
    // Measurement iterations
    for (times, 0..) |*time, i| {
        const start = std.time.microTimestamp();
        const output = try zmin.minifyWithMode(allocator, dataset, mode);
        const end = std.time.microTimestamp();
        
        time.* = @intCast(end - start);
        
        if (i == 0) {
            output_size = output.len;
        }
        
        // TODO: Track peak memory usage
        peak_memory = @max(peak_memory, dataset.len + output.len);
        
        allocator.free(output);
    }
    
    // Calculate statistics
    std.sort.heap(u64, times, {}, std.sort.asc(u64));
    
    const min_time = times[0];
    const max_time = times[times.len - 1];
    const median_time = times[times.len / 2];
    
    var sum: u64 = 0;
    for (times) |time| {
        sum += time;
    }
    const avg_time = sum / times.len;
    
    // Calculate standard deviation
    var variance: f64 = 0;
    for (times) |time| {
        const diff = @as(f64, @floatFromInt(time)) - @as(f64, @floatFromInt(avg_time));
        variance += diff * diff;
    }
    const stddev = @sqrt(variance / @as(f64, @floatFromInt(times.len)));
    
    // Calculate throughput
    const input_mb = @as(f64, @floatFromInt(dataset.len)) / (1024.0 * 1024.0);
    const min_throughput = input_mb / (@as(f64, @floatFromInt(max_time)) / 1_000_000.0);
    const max_throughput = input_mb / (@as(f64, @floatFromInt(min_time)) / 1_000_000.0);
    const avg_throughput = input_mb / (@as(f64, @floatFromInt(avg_time)) / 1_000_000.0);
    
    const numa_detector = @import("../../src/performance/numa_detector.zig");
    const topology = try numa_detector.detect(allocator);
    defer topology.deinit();
    
    return BenchmarkResult{
        .mode = mode,
        .dataset_size = categorizeDatasetSize(dataset.len),
        .input_bytes = dataset.len,
        .output_bytes = output_size,
        .compression_ratio = 1.0 - (@as(f64, @floatFromInt(output_size)) / @as(f64, @floatFromInt(dataset.len))),
        .iterations = config.iterations,
        .min_time_us = min_time,
        .max_time_us = max_time,
        .avg_time_us = avg_time,
        .median_time_us = median_time,
        .stddev_time_us = stddev,
        .min_throughput_mbps = min_throughput,
        .max_throughput_mbps = max_throughput,
        .avg_throughput_mbps = avg_throughput,
        .peak_memory_bytes = peak_memory,
        .cpu_cores = std.Thread.getCpuCount() catch 1,
        .numa_nodes = topology.node_count,
    };
}

/// Generate test dataset of specified size
fn generateDataset(allocator: std.mem.Allocator, size: DatasetSize) ![]u8 {
    const target_size = size.getTargetSize();
    
    // Generate realistic JSON data
    var json = std.ArrayList(u8).init(allocator);
    defer json.deinit();
    
    try json.appendSlice("{\n");
    try json.appendSlice("  \"metadata\": {\n");
    try json.appendSlice("    \"version\": \"1.0\",\n");
    try json.appendSlice("    \"generated\": \"2025-07-26\",\n");
    try json.appendSlice("    \"size\": \"");
    try json.appendSlice(size.getDescription());
    try json.appendSlice("\"\n");
    try json.appendSlice("  },\n");
    try json.appendSlice("  \"items\": [\n");
    
    var item_count: u32 = 0;
    while (json.items.len < target_size - 100) : (item_count += 1) {
        if (item_count > 0) try json.appendSlice(",\n");
        
        try json.appendSlice("    {\n");
        try json.writer().print("      \"id\": {d},\n", .{item_count});
        try json.writer().print("      \"name\": \"Item {d}\",\n", .{item_count});
        try json.writer().print("      \"value\": {d},\n", .{item_count * 42});
        try json.appendSlice("      \"nested\": {\n");
        try json.appendSlice("        \"field1\": \"test data\",\n");
        try json.appendSlice("        \"field2\": [1, 2, 3, 4, 5],\n");
        try json.appendSlice("        \"field3\": true\n");
        try json.appendSlice("      }\n");
        try json.appendSlice("    }");
    }
    
    try json.appendSlice("\n  ]\n}\n");
    
    return json.toOwnedSlice();
}

/// Categorize dataset size
fn categorizeDatasetSize(size: usize) DatasetSize {
    if (size < 1024) return .tiny;
    if (size < 100 * 1024) return .small;
    if (size < 10 * 1024 * 1024) return .medium;
    if (size < 100 * 1024 * 1024) return .large;
    return .xlarge;
}