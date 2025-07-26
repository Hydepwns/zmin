//! Performance Comparison and Regression Detection
//!
//! This module compares benchmark results to detect performance regressions
//! and improvements between different versions or configurations.

const std = @import("std");
const BenchmarkResult = @import("comprehensive_benchmark.zig").BenchmarkResult;

/// Performance comparison result
pub const ComparisonResult = struct {
    baseline: BenchmarkResult,
    current: BenchmarkResult,
    
    // Performance changes
    throughput_change_percent: f64,
    latency_change_percent: f64,
    memory_change_percent: f64,
    
    // Statistical significance
    is_significant: bool,
    confidence_level: f64,
    
    /// Performance change classification
    pub fn classify(self: ComparisonResult) PerformanceChange {
        if (!self.is_significant) return .no_change;
        
        if (self.throughput_change_percent >= 10.0) return .major_improvement;
        if (self.throughput_change_percent >= 5.0) return .improvement;
        if (self.throughput_change_percent <= -10.0) return .major_regression;
        if (self.throughput_change_percent <= -5.0) return .regression;
        
        return .minor_change;
    }
    
    /// Generate comparison summary
    pub fn summary(self: ComparisonResult, writer: anytype) !void {
        const change_type = self.classify();
        const emoji = switch (change_type) {
            .major_improvement => "🚀",
            .improvement => "✅",
            .no_change => "➖",
            .minor_change => "🔸",
            .regression => "⚠️",
            .major_regression => "🔴",
        };
        
        try writer.print("{s} {s} Mode - {s} Dataset: ", .{
            emoji,
            @tagName(self.current.mode),
            @tagName(self.current.dataset_size),
        });
        
        if (self.throughput_change_percent >= 0) {
            try writer.print("+{d:.1}% throughput", .{self.throughput_change_percent});
        } else {
            try writer.print("{d:.1}% throughput", .{self.throughput_change_percent});
        }
        
        try writer.print(" ({d:.2} → {d:.2} MB/s)\n", .{
            self.baseline.avg_throughput_mbps,
            self.current.avg_throughput_mbps,
        });
    }
};

/// Performance change classification
pub const PerformanceChange = enum {
    major_improvement,  // >10% improvement
    improvement,        // 5-10% improvement
    minor_change,       // <5% change
    no_change,          // Not statistically significant
    regression,         // 5-10% regression
    major_regression,   // >10% regression
};

/// Compare two benchmark results
pub fn compareResults(baseline: BenchmarkResult, current: BenchmarkResult) ComparisonResult {
    // Calculate percentage changes
    const throughput_change = ((current.avg_throughput_mbps - baseline.avg_throughput_mbps) / 
                              baseline.avg_throughput_mbps) * 100.0;
    const latency_change = ((@as(f64, @floatFromInt(current.avg_time_us)) - 
                            @as(f64, @floatFromInt(baseline.avg_time_us))) / 
                           @as(f64, @floatFromInt(baseline.avg_time_us))) * 100.0;
    const memory_change = ((@as(f64, @floatFromInt(current.peak_memory_bytes)) - 
                           @as(f64, @floatFromInt(baseline.peak_memory_bytes))) / 
                          @as(f64, @floatFromInt(baseline.peak_memory_bytes))) * 100.0;
    
    // Simple statistical significance test (t-test approximation)
    const is_significant = isStatisticallySignificant(baseline, current);
    
    return ComparisonResult{
        .baseline = baseline,
        .current = current,
        .throughput_change_percent = throughput_change,
        .latency_change_percent = latency_change,
        .memory_change_percent = memory_change,
        .is_significant = is_significant,
        .confidence_level = if (is_significant) 0.95 else 0.0,
    };
}

/// Check if performance difference is statistically significant
fn isStatisticallySignificant(baseline: BenchmarkResult, current: BenchmarkResult) bool {
    // Simple heuristic: consider significant if change is >5% and consistent
    const throughput_change = @abs(current.avg_throughput_mbps - baseline.avg_throughput_mbps) / 
                             baseline.avg_throughput_mbps;
    
    // Check if standard deviations overlap significantly
    const baseline_range = baseline.stddev_time_us * 2.0; // 95% confidence interval
    const current_range = current.stddev_time_us * 2.0;
    
    const baseline_min = @as(f64, @floatFromInt(baseline.avg_time_us)) - baseline_range;
    const baseline_max = @as(f64, @floatFromInt(baseline.avg_time_us)) + baseline_range;
    const current_min = @as(f64, @floatFromInt(current.avg_time_us)) - current_range;
    const current_max = @as(f64, @floatFromInt(current.avg_time_us)) + current_range;
    
    // If ranges don't overlap, it's significant
    const ranges_overlap = (current_min <= baseline_max) and (baseline_min <= current_max);
    
    return throughput_change > 0.05 or !ranges_overlap;
}

/// Compare complete benchmark suites
pub fn compareSuites(
    allocator: std.mem.Allocator,
    baseline_results: []const BenchmarkResult,
    current_results: []const BenchmarkResult,
) !ComparisonReport {
    var report = ComparisonReport.init(allocator);
    errdefer report.deinit();
    
    // Match results by mode and dataset size
    for (current_results) |current| {
        for (baseline_results) |baseline| {
            if (baseline.mode == current.mode and 
                baseline.dataset_size == current.dataset_size) {
                const comparison = compareResults(baseline, current);
                try report.addComparison(comparison);
                break;
            }
        }
    }
    
    report.analyze();
    return report;
}

/// Comprehensive comparison report
pub const ComparisonReport = struct {
    comparisons: std.ArrayList(ComparisonResult),
    
    // Summary statistics
    total_improvements: u32 = 0,
    total_regressions: u32 = 0,
    total_unchanged: u32 = 0,
    
    avg_throughput_change: f64 = 0,
    max_improvement: ?ComparisonResult = null,
    max_regression: ?ComparisonResult = null,
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ComparisonReport {
        return ComparisonReport{
            .comparisons = std.ArrayList(ComparisonResult).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ComparisonReport) void {
        self.comparisons.deinit();
    }
    
    pub fn addComparison(self: *ComparisonReport, comparison: ComparisonResult) !void {
        try self.comparisons.append(comparison);
    }
    
    /// Analyze all comparisons and compute summary statistics
    pub fn analyze(self: *ComparisonReport) void {
        var total_change: f64 = 0;
        var max_improvement_pct: f64 = 0;
        var max_regression_pct: f64 = 0;
        
        for (self.comparisons.items) |comparison| {
            const change_type = comparison.classify();
            switch (change_type) {
                .major_improvement, .improvement => self.total_improvements += 1,
                .major_regression, .regression => self.total_regressions += 1,
                .no_change, .minor_change => self.total_unchanged += 1,
            }
            
            total_change += comparison.throughput_change_percent;
            
            if (comparison.throughput_change_percent > max_improvement_pct) {
                max_improvement_pct = comparison.throughput_change_percent;
                self.max_improvement = comparison;
            }
            
            if (comparison.throughput_change_percent < max_regression_pct) {
                max_regression_pct = comparison.throughput_change_percent;
                self.max_regression = comparison;
            }
        }
        
        if (self.comparisons.items.len > 0) {
            self.avg_throughput_change = total_change / @as(f64, @floatFromInt(self.comparisons.items.len));
        }
    }
    
    /// Generate comparison report
    pub fn generateReport(self: *ComparisonReport, writer: anytype) !void {
        try writer.print("\n📊 Performance Comparison Report\n", .{});
        try writer.print("{'='<|50}\n\n", .{});
        
        // Summary
        try writer.print("Summary:\n", .{});
        try writer.print("  ✅ Improvements: {d}\n", .{self.total_improvements});
        try writer.print("  ⚠️  Regressions: {d}\n", .{self.total_regressions});
        try writer.print("  ➖ No Change: {d}\n", .{self.total_unchanged});
        try writer.print("  📈 Average Change: {d:+.1}%\n\n", .{self.avg_throughput_change});
        
        // Highlights
        if (self.max_improvement) |improvement| {
            try writer.print("🚀 Best Improvement:\n   ", .{});
            try improvement.summary(writer);
        }
        
        if (self.max_regression) |regression| {
            try writer.print("\n🔴 Worst Regression:\n   ", .{});
            try regression.summary(writer);
        }
        
        // Detailed results
        try writer.print("\nDetailed Results:\n", .{});
        try writer.print("{'-'<|50}\n", .{});
        
        for (self.comparisons.items) |comparison| {
            try writer.print("  ", .{});
            try comparison.summary(writer);
        }
        
        // Pass/Fail determination
        try writer.print("\n{'-'<|50}\n", .{});
        if (self.total_regressions == 0) {
            try writer.print("✅ PASS: No performance regressions detected\n", .{});
        } else if (self.avg_throughput_change >= 0) {
            try writer.print("⚠️  PASS WITH WARNINGS: Some regressions, but overall improvement\n", .{});
        } else {
            try writer.print("❌ FAIL: Performance regressions detected\n", .{});
        }
    }
    
    /// Check if any major regressions exist
    pub fn hasMajorRegressions(self: *ComparisonReport) bool {
        for (self.comparisons.items) |comparison| {
            if (comparison.classify() == .major_regression) {
                return true;
            }
        }
        return false;
    }
};

/// Load benchmark results from file
pub fn loadResults(allocator: std.mem.Allocator, path: []const u8) ![]BenchmarkResult {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    
    const contents = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(contents);
    
    // TODO: Parse JSON/CSV results
    _ = contents;
    
    // For now, return empty slice
    return allocator.alloc(BenchmarkResult, 0);
}

/// Save benchmark results to file
pub fn saveResults(results: []const BenchmarkResult, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    
    // TODO: Implement JSON/CSV serialization
    _ = results;
    
    try file.writeAll("# Benchmark Results\n");
}