//! Prometheus metrics exporter for zmin
//!
//! This module provides Prometheus-compatible metrics export functionality
//! for monitoring zmin performance and health.

const std = @import("std");
const http = std.http;

/// Metric types supported by Prometheus
pub const MetricType = enum {
    counter,
    gauge,
    histogram,
    summary,

    pub fn toString(self: MetricType) []const u8 {
        return switch (self) {
            .counter => "counter",
            .gauge => "gauge",
            .histogram => "histogram",
            .summary => "summary",
        };
    }
};

/// Individual metric definition
pub const Metric = struct {
    name: []const u8,
    help: []const u8,
    type: MetricType,
    value: f64,
    labels: ?std.StringHashMap([]const u8) = null,
};

/// Prometheus exporter
pub const PrometheusExporter = struct {
    allocator: std.mem.Allocator,
    metrics: std.ArrayList(Metric),
    port: u16,
    server: ?*std.http.Server = null,

    pub fn init(allocator: std.mem.Allocator, port: u16) PrometheusExporter {
        return .{
            .allocator = allocator,
            .metrics = std.ArrayList(Metric).init(allocator),
            .port = port,
        };
    }

    pub fn deinit(self: *PrometheusExporter) void {
        self.metrics.deinit();
        if (self.server) |server| {
            server.deinit();
        }
    }

    /// Register a new metric
    pub fn registerMetric(self: *PrometheusExporter, metric: Metric) !void {
        try self.metrics.append(metric);
    }

    /// Update an existing metric value
    pub fn updateMetric(self: *PrometheusExporter, name: []const u8, value: f64) void {
        for (self.metrics.items) |*metric| {
            if (std.mem.eql(u8, metric.name, name)) {
                metric.value = value;
                return;
            }
        }
    }

    /// Increment a counter metric
    pub fn incrementCounter(self: *PrometheusExporter, name: []const u8, value: f64) void {
        for (self.metrics.items) |*metric| {
            if (std.mem.eql(u8, metric.name, name) and metric.type == .counter) {
                metric.value += value;
                return;
            }
        }
    }

    /// Generate Prometheus exposition format
    pub fn generateMetrics(self: *PrometheusExporter, writer: anytype) !void {
        for (self.metrics.items) |metric| {
            // Write HELP line
            try writer.print("# HELP {s} {s}\n", .{ metric.name, metric.help });
            
            // Write TYPE line
            try writer.print("# TYPE {s} {s}\n", .{ metric.name, metric.type.toString() });
            
            // Write metric value
            if (metric.labels) |labels| {
                try writer.print("{s}{{", .{metric.name});
                var iter = labels.iterator();
                var first = true;
                while (iter.next()) |entry| {
                    if (!first) try writer.writeAll(",");
                    try writer.print("{s}=\"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
                    first = false;
                }
                try writer.print("}} {d}\n", .{metric.value});
            } else {
                try writer.print("{s} {d}\n", .{ metric.name, metric.value });
            }
        }
    }

    /// Start HTTP server for metrics endpoint
    pub fn startServer(self: *PrometheusExporter) !void {
        // Implementation would require HTTP server setup
        // This is a placeholder for the actual implementation
        _ = self;
        @panic("HTTP server not implemented");
    }
};

/// Common zmin metrics
pub const ZminMetrics = struct {
    // Performance metrics
    pub const throughput_mbps = Metric{
        .name = "zmin_throughput_mbps",
        .help = "Current throughput in MB/s",
        .type = .gauge,
        .value = 0,
    };

    pub const processing_time_seconds = Metric{
        .name = "zmin_processing_time_seconds",
        .help = "Time taken to process JSON",
        .type = .histogram,
        .value = 0,
    };

    pub const memory_usage_bytes = Metric{
        .name = "zmin_memory_usage_bytes",
        .help = "Current memory usage in bytes",
        .type = .gauge,
        .value = 0,
    };

    // Error metrics
    pub const errors_total = Metric{
        .name = "zmin_errors_total",
        .help = "Total number of processing errors",
        .type = .counter,
        .value = 0,
    };

    // Mode-specific metrics
    pub const mode_usage_total = Metric{
        .name = "zmin_mode_usage_total",
        .help = "Number of times each mode has been used",
        .type = .counter,
        .value = 0,
    };

    // GPU metrics
    pub const gpu_enabled = Metric{
        .name = "zmin_gpu_enabled",
        .help = "Whether GPU acceleration is enabled",
        .type = .gauge,
        .value = 0,
    };

    pub const gpu_utilization_percent = Metric{
        .name = "zmin_gpu_utilization_percent",
        .help = "GPU utilization percentage",
        .type = .gauge,
        .value = 0,
    };

    pub const gpu_memory_used_bytes = Metric{
        .name = "zmin_gpu_memory_used_bytes",
        .help = "GPU memory usage in bytes",
        .type = .gauge,
        .value = 0,
    };
};

test "PrometheusExporter basic functionality" {
    var exporter = PrometheusExporter.init(std.testing.allocator, 8080);
    defer exporter.deinit();

    try exporter.registerMetric(ZminMetrics.throughput_mbps);
    try exporter.registerMetric(ZminMetrics.errors_total);

    exporter.updateMetric("zmin_throughput_mbps", 1500.5);
    exporter.incrementCounter("zmin_errors_total", 1);

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try exporter.generateMetrics(buffer.writer());
    
    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "zmin_throughput_mbps 1500.5") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "zmin_errors_total 1") != null);
}