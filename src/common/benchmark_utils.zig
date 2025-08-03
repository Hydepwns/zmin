//! Common Benchmark Utilities
//!
//! This module provides reusable benchmarking utilities to eliminate
//! duplicate timing and measurement code across the codebase.

const std = @import("std");
const constants = @import("constants.zig");

/// Benchmark result structure
pub const BenchmarkResult = struct {
    /// Name of the benchmark
    name: []const u8 = "",
    
    /// Elapsed time in nanoseconds
    elapsed_ns: u64,
    
    /// Bytes processed
    bytes_processed: usize,
    
    /// Operations performed
    operations: usize = 0,
    
    /// Throughput in MB/s
    throughput_mbps: f64,
    
    /// Operations per second
    ops_per_second: f64 = 0,
    
    /// Latency per operation (ns)
    latency_ns: f64 = 0,
    
    /// Memory usage peak
    peak_memory: usize = 0,
    
    /// Format result as string
    pub fn format(
        self: BenchmarkResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("{s}: {d:.2} MB/s", .{
            self.name,
            self.throughput_mbps,
        });
        
        if (self.operations > 0) {
            try writer.print(" ({d:.0} ops/s, {d:.2} ns/op)", .{
                self.ops_per_second,
                self.latency_ns,
            });
        }
        
        if (self.peak_memory > 0) {
            try writer.print(" [peak mem: {}]", .{
                std.fmt.fmtIntSizeDec(self.peak_memory),
            });
        }
    }
};

/// Simple benchmark timer
pub const Timer = struct {
    start_time: i128,
    
    /// Start timing
    pub fn start() Timer {
        return .{ .start_time = std.time.nanoTimestamp() };
    }
    
    /// End timing and get elapsed nanoseconds
    pub fn end(self: Timer) u64 {
        const end_time = std.time.nanoTimestamp();
        return @intCast(end_time - self.start_time);
    }
    
    /// End timing and calculate result
    pub fn endWithResult(self: Timer, bytes_processed: usize) BenchmarkResult {
        const elapsed_ns = self.end();
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / constants.Time.NS_PER_SECOND;
        const throughput_mbps = @as(f64, @floatFromInt(bytes_processed)) / (1024.0 * 1024.0) / elapsed_s;
        
        return BenchmarkResult{
            .elapsed_ns = elapsed_ns,
            .bytes_processed = bytes_processed,
            .throughput_mbps = throughput_mbps,
        };
    }
};

/// Advanced benchmark timer with statistics
pub const BenchmarkTimer = struct {
    name: []const u8,
    samples: std.ArrayList(u64),
    bytes_per_sample: usize,
    operations_per_sample: usize = 0,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) BenchmarkTimer {
        return .{
            .name = name,
            .samples = std.ArrayList(u64).init(allocator),
            .bytes_per_sample = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *BenchmarkTimer) void {
        self.samples.deinit();
    }
    
    /// Run a single benchmark iteration
    pub fn runIteration(
        self: *BenchmarkTimer,
        comptime func: anytype,
        args: anytype,
        bytes_processed: usize,
    ) !void {
        const timer = Timer.start();
        _ = try @call(.auto, func, args);
        const elapsed = timer.end();
        
        try self.samples.append(elapsed);
        self.bytes_per_sample = bytes_processed;
    }
    
    /// Run benchmark with warmup and multiple iterations
    pub fn runBenchmark(
        self: *BenchmarkTimer,
        comptime func: anytype,
        args: anytype,
        bytes_processed: usize,
        config: BenchmarkConfig,
    ) !BenchmarkResult {
        // Warmup
        for (0..config.warmup_iterations) |_| {
            _ = try @call(.auto, func, args);
        }
        
        // Clear any previous samples
        self.samples.clearRetainingCapacity();
        
        // Measurement iterations
        for (0..config.measure_iterations) |_| {
            try self.runIteration(func, args, bytes_processed);
        }
        
        return self.getResult();
    }
    
    /// Get benchmark result with statistics
    pub fn getResult(self: *BenchmarkTimer) BenchmarkResult {
        if (self.samples.items.len == 0) {
            return BenchmarkResult{
                .name = self.name,
                .elapsed_ns = 0,
                .bytes_processed = 0,
                .throughput_mbps = 0,
            };
        }
        
        // Calculate statistics
        const stats = calculateStats(self.samples.items);
        
        // Use median for more stable results
        const elapsed_s = stats.median / constants.Time.NS_PER_SECOND;
        const throughput_mbps = @as(f64, @floatFromInt(self.bytes_per_sample)) / (1024.0 * 1024.0) / elapsed_s;
        
        var result = BenchmarkResult{
            .name = self.name,
            .elapsed_ns = @intFromFloat(stats.median),
            .bytes_processed = self.bytes_per_sample,
            .throughput_mbps = throughput_mbps,
        };
        
        if (self.operations_per_sample > 0) {
            result.operations = self.operations_per_sample;
            result.ops_per_second = @as(f64, @floatFromInt(self.operations_per_sample)) / elapsed_s;
            result.latency_ns = stats.median / @as(f64, @floatFromInt(self.operations_per_sample));
        }
        
        return result;
    }
};

/// Benchmark configuration
pub const BenchmarkConfig = struct {
    warmup_iterations: usize = constants.Performance.WARMUP_ITERATIONS,
    measure_iterations: usize = constants.Performance.MEASURE_ITERATIONS,
    min_runtime_ns: u64 = 1_000_000_000, // 1 second minimum
    max_runtime_ns: u64 = 10_000_000_000, // 10 seconds maximum
};

/// Statistics for benchmark samples
pub const Stats = struct {
    min: f64,
    max: f64,
    mean: f64,
    median: f64,
    stddev: f64,
    
    pub fn format(
        self: Stats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("min={d:.2}ms, max={d:.2}ms, mean={d:.2}ms, median={d:.2}ms, stddev={d:.2}ms", .{
            self.min / constants.Time.NS_PER_MS,
            self.max / constants.Time.NS_PER_MS,
            self.mean / constants.Time.NS_PER_MS,
            self.median / constants.Time.NS_PER_MS,
            self.stddev / constants.Time.NS_PER_MS,
        });
    }
};

/// Calculate statistics from samples
fn calculateStats(samples: []const u64) Stats {
    if (samples.len == 0) {
        return Stats{
            .min = 0,
            .max = 0,
            .mean = 0,
            .median = 0,
            .stddev = 0,
        };
    }
    
    // Convert to floats for calculation
    var float_samples = std.ArrayList(f64).init(std.heap.page_allocator);
    defer float_samples.deinit();
    
    var sum: f64 = 0;
    var min: f64 = std.math.floatMax(f64);
    var max: f64 = 0;
    
    for (samples) |sample| {
        const f = @as(f64, @floatFromInt(sample));
        float_samples.append(f) catch {};
        sum += f;
        min = @min(min, f);
        max = @max(max, f);
    }
    
    const mean = sum / @as(f64, @floatFromInt(samples.len));
    
    // Calculate median
    std.mem.sort(f64, float_samples.items, {}, comptime std.sort.asc(f64));
    const median = if (float_samples.items.len % 2 == 0)
        (float_samples.items[float_samples.items.len / 2 - 1] + float_samples.items[float_samples.items.len / 2]) / 2
    else
        float_samples.items[float_samples.items.len / 2];
    
    // Calculate standard deviation
    var variance: f64 = 0;
    for (float_samples.items) |sample| {
        const diff = sample - mean;
        variance += diff * diff;
    }
    variance /= @as(f64, @floatFromInt(samples.len));
    const stddev = @sqrt(variance);
    
    return Stats{
        .min = min,
        .max = max,
        .mean = mean,
        .median = median,
        .stddev = stddev,
    };
}

/// Benchmark runner for comparing multiple implementations
pub const BenchmarkSuite = struct {
    name: []const u8,
    allocator: std.mem.Allocator,
    results: std.ArrayList(BenchmarkResult),
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) BenchmarkSuite {
        return .{
            .name = name,
            .allocator = allocator,
            .results = std.ArrayList(BenchmarkResult).init(allocator),
        };
    }
    
    pub fn deinit(self: *BenchmarkSuite) void {
        self.results.deinit();
    }
    
    /// Add a benchmark to the suite
    pub fn addBenchmark(
        self: *BenchmarkSuite,
        name: []const u8,
        comptime func: anytype,
        args: anytype,
        bytes_processed: usize,
    ) !void {
        var timer = BenchmarkTimer.init(self.allocator, name);
        defer timer.deinit();
        
        const result = try timer.runBenchmark(func, args, bytes_processed, .{});
        try self.results.append(result);
    }
    
    /// Print comparison results
    pub fn printResults(self: *BenchmarkSuite) void {
        std.debug.print("\n=== {s} ===\n", .{self.name});
        
        // Find best result
        var best_throughput: f64 = 0;
        for (self.results.items) |result| {
            best_throughput = @max(best_throughput, result.throughput_mbps);
        }
        
        // Print results with relative performance
        for (self.results.items) |result| {
            const relative = (result.throughput_mbps / best_throughput) * 100;
            std.debug.print("{}: {d:.0}%\n", .{ result, relative });
        }
    }
};

/// Memory tracking wrapper for benchmarks
pub const MemoryTracker = struct {
    base_allocator: std.mem.Allocator,
    current_usage: usize = 0,
    peak_usage: usize = 0,
    allocation_count: usize = 0,
    
    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    };
    
    pub fn allocator(self: *MemoryTracker) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }
    
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *MemoryTracker = @ptrCast(@alignCast(ctx));
        const result = self.base_allocator.rawAlloc(len, ptr_align, ret_addr);
        
        if (result) |_| {
            self.current_usage += len;
            self.peak_usage = @max(self.peak_usage, self.current_usage);
            self.allocation_count += 1;
        }
        
        return result;
    }
    
    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *MemoryTracker = @ptrCast(@alignCast(ctx));
        const result = self.base_allocator.rawResize(buf, buf_align, new_len, ret_addr);
        
        if (result) {
            self.current_usage = self.current_usage - buf.len + new_len;
            self.peak_usage = @max(self.peak_usage, self.current_usage);
        }
        
        return result;
    }
    
    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *MemoryTracker = @ptrCast(@alignCast(ctx));
        self.base_allocator.rawFree(buf, buf_align, ret_addr);
        self.current_usage -|= buf.len;
    }
    
    pub fn reset(self: *MemoryTracker) void {
        self.current_usage = 0;
        self.peak_usage = 0;
        self.allocation_count = 0;
    }
};

/// Run a function and measure its performance
pub fn measurePerformance(
    comptime func: anytype,
    args: anytype,
    bytes_processed: usize,
) !BenchmarkResult {
    const timer = Timer.start();
    _ = try @call(.auto, func, args);
    return timer.endWithResult(bytes_processed);
}

/// Run a function with memory tracking
pub fn measureWithMemory(
    allocator: std.mem.Allocator,
    comptime func: anytype,
    args: anytype,
    bytes_processed: usize,
) !BenchmarkResult {
    var tracker = MemoryTracker{ .base_allocator = allocator };
    const tracking_allocator = tracker.allocator();
    
    // Replace allocator in args if it has one
    var modified_args = args;
    if (@hasField(@TypeOf(args), "allocator")) {
        modified_args.allocator = tracking_allocator;
    }
    
    const timer = Timer.start();
    _ = try @call(.auto, func, modified_args);
    var result = timer.endWithResult(bytes_processed);
    
    result.peak_memory = tracker.peak_usage;
    return result;
}

// Tests
test "Timer basic usage" {
    const timer = Timer.start();
    std.time.sleep(10_000_000); // 10ms
    const elapsed = timer.end();
    
    try std.testing.expect(elapsed >= 10_000_000);
}

test "BenchmarkTimer statistics" {
    var timer = BenchmarkTimer.init(std.testing.allocator, "test");
    defer timer.deinit();
    
    // Add some samples
    try timer.samples.append(1000);
    try timer.samples.append(2000);
    try timer.samples.append(3000);
    timer.bytes_per_sample = 1024;
    
    const result = timer.getResult();
    try std.testing.expectEqual(@as(usize, 1024), result.bytes_processed);
    try std.testing.expect(result.throughput_mbps > 0);
}

test "MemoryTracker" {
    var tracker = MemoryTracker{ .base_allocator = std.testing.allocator };
    const tracking_allocator = tracker.allocator();
    
    const data = try tracking_allocator.alloc(u8, 1024);
    defer tracking_allocator.free(data);
    
    try std.testing.expectEqual(@as(usize, 1024), tracker.current_usage);
    try std.testing.expectEqual(@as(usize, 1024), tracker.peak_usage);
    try std.testing.expectEqual(@as(usize, 1), tracker.allocation_count);
}