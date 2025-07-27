//! Telemetry and metrics collection for zmin
//!
//! This module provides optional telemetry collection for performance monitoring
//! and usage analytics. All telemetry is opt-in and privacy-respecting.

const std = @import("std");

/// Telemetry configuration
pub const TelemetryConfig = struct {
    /// Enable telemetry collection
    enabled: bool = false,
    /// Send anonymous usage statistics
    anonymous_stats: bool = false,
    /// Local metrics file path (optional)
    metrics_file: ?[]const u8 = null,
    /// Remote endpoint for metrics (optional)
    remote_endpoint: ?[]const u8 = null,
    /// Sample rate (0.0 to 1.0)
    sample_rate: f32 = 0.1,
};

/// Performance metrics for a minification operation
pub const PerformanceMetrics = struct {
    /// Input size in bytes
    input_size: usize,
    /// Output size in bytes
    output_size: usize,
    /// Processing time in nanoseconds
    processing_time_ns: u64,
    /// Processing mode used
    mode: []const u8,
    /// SIMD features detected
    simd_features: []const u8,
    /// Number of threads used
    thread_count: u32,
    /// Memory usage peak in bytes
    peak_memory_bytes: usize,
    /// Timestamp when operation started
    timestamp: i64,
    /// Success/failure status
    success: bool,
    /// Error message if failed
    error_message: ?[]const u8 = null,
};

/// System information for telemetry
pub const SystemInfo = struct {
    /// Operating system
    os: []const u8,
    /// CPU architecture
    arch: []const u8,
    /// CPU count
    cpu_count: u32,
    /// Available memory in bytes
    memory_bytes: usize,
    /// zmin version
    version: []const u8,
    /// Compiled with optimization level
    optimization: []const u8,
};

/// Telemetry collector
pub const TelemetryCollector = struct {
    allocator: std.mem.Allocator,
    config: TelemetryConfig,
    system_info: SystemInfo,
    metrics_buffer: std.ArrayList(PerformanceMetrics),
    mutex: std.Thread.Mutex = .{},
    
    pub fn init(allocator: std.mem.Allocator, config: TelemetryConfig) !TelemetryCollector {
        return TelemetryCollector{
            .allocator = allocator,
            .config = config,
            .system_info = try collectSystemInfo(allocator),
            .metrics_buffer = std.ArrayList(PerformanceMetrics).init(allocator),
        };
    }
    
    pub fn deinit(self: *TelemetryCollector) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Flush any remaining metrics
        if (self.config.enabled and self.metrics_buffer.items.len > 0) {
            self.flushMetrics() catch {};
        }
        
        self.metrics_buffer.deinit();
    }
    
    /// Record a performance metric
    pub fn recordPerformance(self: *TelemetryCollector, metrics: PerformanceMetrics) !void {
        if (!self.config.enabled) return;
        
        // Sample based on sample rate
        if (std.crypto.random.float(f32) > self.config.sample_rate) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.metrics_buffer.append(metrics);
        
        // Flush if buffer is getting large
        if (self.metrics_buffer.items.len >= 100) {
            try self.flushMetrics();
        }
    }
    
    /// Flush metrics to configured destinations
    fn flushMetrics(self: *TelemetryCollector) !void {
        if (self.metrics_buffer.items.len == 0) return;
        
        // Write to local file if configured
        if (self.config.metrics_file) |file_path| {
            try self.writeMetricsToFile(file_path);
        }
        
        // Send to remote endpoint if configured
        if (self.config.remote_endpoint) |endpoint| {
            try self.sendMetricsToRemote(endpoint);
        }
        
        self.metrics_buffer.clearRetainingCapacity();
    }
    
    fn writeMetricsToFile(self: *TelemetryCollector, file_path: []const u8) !void {
        const file = std.fs.cwd().createFile(file_path, .{ .truncate = false }) catch |err| switch (err) {
            error.FileNotFound => {
                // Create parent directories if needed
                if (std.fs.path.dirname(file_path)) |dir| {
                    std.fs.cwd().makePath(dir) catch {};
                }
                return std.fs.cwd().createFile(file_path, .{});
            },
            else => return err,
        };
        defer file.close();
        
        // Seek to end of file for appending
        try file.seekFromEnd(0);
        
        const writer = file.writer();
        
        // Write JSON Lines format
        for (self.metrics_buffer.items) |metric| {
            try std.json.stringify(metric, .{}, writer);
            try writer.writeByte('\n');
        }
    }
    
    fn sendMetricsToRemote(self: *TelemetryCollector, endpoint: []const u8) !void {
        // In a real implementation, this would send metrics to a remote endpoint
        // For now, just log that we would send them
        _ = endpoint;
        std.log.info("Would send {} metrics to remote endpoint", .{self.metrics_buffer.items.len});
    }
};

/// Collect system information for telemetry
fn collectSystemInfo(allocator: std.mem.Allocator) !SystemInfo {
    _ = allocator;
    
    const builtin = @import("builtin");
    
    return SystemInfo{
        .os = switch (builtin.os.tag) {
            .linux => "linux",
            .macos => "macos", 
            .windows => "windows",
            .freebsd => "freebsd",
            else => "other",
        },
        .arch = switch (builtin.cpu.arch) {
            .x86_64 => "x86_64",
            .aarch64 => "aarch64",
            .arm => "arm",
            else => "other",
        },
        .cpu_count = @intCast(std.Thread.getCpuCount() catch 1),
        .memory_bytes = getTotalMemory(),
        .version = "0.1.0", // TODO: Get from build system
        .optimization = switch (builtin.mode) {
            .Debug => "debug",
            .ReleaseSafe => "release_safe", 
            .ReleaseFast => "release_fast",
            .ReleaseSmall => "release_small",
        },
    };
}

/// Get total system memory (best effort)
fn getTotalMemory() usize {
    // This is a simplified implementation
    // In practice, you'd use platform-specific APIs
    return 8 * 1024 * 1024 * 1024; // 8GB default
}

/// Create a performance metric from timing data
pub fn createPerformanceMetric(
    input_size: usize,
    output_size: usize,
    start_time: i64,
    end_time: i64,
    mode: []const u8,
    simd_features: []const u8,
    thread_count: u32,
    peak_memory: usize,
    success: bool,
    error_msg: ?[]const u8,
) PerformanceMetrics {
    return PerformanceMetrics{
        .input_size = input_size,
        .output_size = output_size,
        .processing_time_ns = @intCast(end_time - start_time),
        .mode = mode,
        .simd_features = simd_features,
        .thread_count = thread_count,
        .peak_memory_bytes = peak_memory,
        .timestamp = start_time,
        .success = success,
        .error_message = error_msg,
    };
}

/// Global telemetry instance (optional)
var global_telemetry: ?*TelemetryCollector = null;

/// Initialize global telemetry
pub fn initGlobalTelemetry(allocator: std.mem.Allocator, config: TelemetryConfig) !void {
    if (global_telemetry != null) return;
    
    global_telemetry = try allocator.create(TelemetryCollector);
    global_telemetry.?.* = try TelemetryCollector.init(allocator, config);
}

/// Deinitialize global telemetry
pub fn deinitGlobalTelemetry(allocator: std.mem.Allocator) void {
    if (global_telemetry) |telemetry| {
        telemetry.deinit();
        allocator.destroy(telemetry);
        global_telemetry = null;
    }
}

/// Record performance metric using global telemetry
pub fn recordGlobalPerformance(metrics: PerformanceMetrics) void {
    if (global_telemetry) |telemetry| {
        telemetry.recordPerformance(metrics) catch {};
    }
}

/// Check if telemetry is enabled via environment variables
pub fn isTelemetryEnabled() bool {
    // Check for opt-out environment variable
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "ZMIN_TELEMETRY_DISABLE")) |_| {
        return false;
    } else |_| {}
    
    // Check for opt-in environment variable
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "ZMIN_TELEMETRY_ENABLE")) |_| {
        return true;
    } else |_| {}
    
    // Default to disabled for privacy
    return false;
}

/// Load telemetry configuration from environment
pub fn loadTelemetryConfig(allocator: std.mem.Allocator) TelemetryConfig {
    _ = allocator;
    
    var config = TelemetryConfig{};
    
    // Check if telemetry is enabled
    config.enabled = isTelemetryEnabled();
    
    // Check for anonymous stats preference
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "ZMIN_ANONYMOUS_STATS")) |value| {
        defer std.heap.page_allocator.free(value);
        config.anonymous_stats = std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true");
    } else |_| {}
    
    // Check for metrics file path
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "ZMIN_METRICS_FILE")) |value| {
        defer std.heap.page_allocator.free(value);
        // TODO: Clone the value to persist beyond this function
        config.metrics_file = value;
    } else |_| {}
    
    // Check for sample rate
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "ZMIN_SAMPLE_RATE")) |value| {
        defer std.heap.page_allocator.free(value);
        config.sample_rate = std.fmt.parseFloat(f32, value) catch 0.1;
    } else |_| {}
    
    return config;
}