//! Shared Configuration Structures
//!
//! This module provides common configuration structures and utilities
//! to ensure consistency across different minifier implementations.

const std = @import("std");
const builtin = @import("builtin");

/// Base configuration that all minifiers should support
pub const BaseConfig = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,
    
    /// Performance settings
    performance: PerformanceConfig = .{},
    
    /// Validation settings
    validation: ValidationConfig = .{},
    
    /// Memory settings
    memory: MemoryConfig = .{},
    
    /// Debug/monitoring settings
    debug: DebugConfig = .{},
};

/// Performance-related configuration
pub const PerformanceConfig = struct {
    /// Optimization level
    optimization_level: OptimizationLevel = .automatic,
    
    /// Enable SIMD optimizations
    enable_simd: bool = true,
    
    /// Enable parallel processing
    enable_parallel: bool = true,
    
    /// Number of threads (0 = auto-detect)
    thread_count: usize = 0,
    
    /// Chunk size for processing
    chunk_size: usize = 64 * 1024,
    
    /// Minimum chunk size
    min_chunk_size: usize = 1024,
    
    /// Maximum chunk size
    max_chunk_size: usize = 1024 * 1024,
    
    /// Target throughput (MB/s, 0 = no target)
    target_throughput_mbps: f64 = 0,
    
    /// Maximum latency (ms, 0 = no limit)
    max_latency_ms: u32 = 0,
};

/// Optimization levels
pub const OptimizationLevel = enum {
    /// No optimizations
    none,
    
    /// Basic optimizations (safe, compatible)
    basic,
    
    /// Balanced performance/compatibility
    balanced,
    
    /// Maximum performance
    turbo,
    
    /// Automatic selection based on input
    automatic,
    
    /// Memory-efficient mode
    eco,
    
    pub fn getDescription(self: OptimizationLevel) []const u8 {
        return switch (self) {
            .none => "No optimizations",
            .basic => "Basic optimizations",
            .balanced => "Balanced performance",
            .turbo => "Maximum performance",
            .automatic => "Automatic selection",
            .eco => "Memory efficient",
        };
    }
};

/// Validation configuration
pub const ValidationConfig = struct {
    /// Validate input JSON
    validate_input: bool = true,
    
    /// Validate output JSON
    validate_output: bool = false,
    
    /// Strict mode (fail on warnings)
    strict_mode: bool = false,
    
    /// Allow comments in JSON
    allow_comments: bool = false,
    
    /// Allow trailing commas
    allow_trailing_commas: bool = false,
    
    /// Maximum nesting depth
    max_depth: u32 = 1000,
    
    /// Preserve number precision
    preserve_precision: bool = true,
};

/// Memory configuration
pub const MemoryConfig = struct {
    /// Memory strategy
    strategy: MemoryStrategy = .adaptive,
    
    /// Pre-allocate buffers
    preallocate: bool = true,
    
    /// Initial buffer size
    initial_buffer_size: usize = 64 * 1024,
    
    /// Maximum buffer size (0 = no limit)
    max_buffer_size: usize = 0,
    
    /// Use huge pages if available
    use_huge_pages: bool = false,
    
    /// NUMA awareness
    numa_aware: bool = false,
    
    /// Memory limit (bytes, 0 = no limit)
    memory_limit: usize = 0,
};

/// Memory allocation strategies
pub const MemoryStrategy = enum {
    /// Standard allocation
    standard,
    
    /// Pool-based allocation
    pooled,
    
    /// Arena allocation
    arena,
    
    /// Adaptive (choose based on input)
    adaptive,
    
    /// Stack-based (for small inputs)
    stack,
    
    pub fn getDescription(self: MemoryStrategy) []const u8 {
        return switch (self) {
            .standard => "Standard allocation",
            .pooled => "Pool-based allocation",
            .arena => "Arena allocation",
            .adaptive => "Adaptive allocation",
            .stack => "Stack-based allocation",
        };
    }
};

/// Debug and monitoring configuration
pub const DebugConfig = struct {
    /// Enable performance monitoring
    enable_monitoring: bool = false,
    
    /// Enable detailed logging
    enable_logging: bool = false,
    
    /// Log level
    log_level: LogLevel = .info,
    
    /// Collect statistics
    collect_stats: bool = false,
    
    /// Profile memory usage
    profile_memory: bool = false,
    
    /// Profile CPU usage
    profile_cpu: bool = false,
    
    /// Benchmark mode
    benchmark_mode: bool = false,
};

/// Log levels
pub const LogLevel = enum {
    trace,
    debug,
    info,
    warn,
    err,
    critical,
    
    pub fn getPrefix(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "[TRACE]",
            .debug => "[DEBUG]",
            .info => "[INFO]",
            .warn => "[WARN]",
            .err => "[ERROR]",
            .critical => "[CRITICAL]",
        };
    }
};

/// Mode-specific configurations
pub const ModeConfig = union(enum) {
    /// Standard mode
    standard: StandardConfig,
    
    /// Streaming mode
    streaming: StreamingConfig,
    
    /// Parallel mode
    parallel: ParallelConfig,
    
    /// Turbo mode
    turbo: TurboConfig,
    
    /// ECO mode
    eco: EcoConfig,
};

/// Standard mode configuration
pub const StandardConfig = struct {
    /// Use BaseConfig fields
    base: BaseConfig,
};

/// Streaming mode configuration
pub const StreamingConfig = struct {
    /// Use BaseConfig fields
    base: BaseConfig,
    
    /// Buffer size for streaming
    buffer_size: usize = 8 * 1024,
    
    /// Flush threshold
    flush_threshold: usize = 4 * 1024,
    
    /// Enable backpressure
    enable_backpressure: bool = true,
};

/// Parallel mode configuration
pub const ParallelConfig = struct {
    /// Use BaseConfig fields
    base: BaseConfig,
    
    /// Worker thread count
    worker_count: usize = 0,
    
    /// Work queue size
    queue_size: usize = 1000,
    
    /// Work stealing enabled
    work_stealing: bool = true,
    
    /// CPU pinning
    pin_threads: bool = false,
};

/// Turbo mode configuration
pub const TurboConfig = struct {
    /// Use BaseConfig fields
    base: BaseConfig,
    
    /// Aggressive optimizations
    aggressive: bool = true,
    
    /// Unsafe optimizations
    allow_unsafe: bool = false,
    
    /// Speculation depth
    speculation_depth: u32 = 4,
    
    /// Prefetch distance
    prefetch_distance: u32 = 8,
};

/// ECO mode configuration  
pub const EcoConfig = struct {
    /// Use BaseConfig fields
    base: BaseConfig,
    
    /// Target memory usage (bytes)
    target_memory: usize = 10 * 1024 * 1024,
    
    /// Aggressive GC
    aggressive_gc: bool = true,
    
    /// Swap to disk threshold
    swap_threshold: usize = 100 * 1024 * 1024,
};

/// Configuration builder for fluent API
pub fn ConfigBuilder(comptime T: type) type {
    return struct {
        config: T,
        
        const Self = @This();
        
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .config = T{
                    .allocator = allocator,
                },
            };
        }
        
        pub fn withOptimizationLevel(self: Self, level: OptimizationLevel) Self {
            var config = self;
            if (@hasField(T, "performance")) {
                config.config.performance.optimization_level = level;
            }
            return config;
        }
        
        pub fn withThreadCount(self: Self, count: usize) Self {
            var config = self;
            if (@hasField(T, "performance")) {
                config.config.performance.thread_count = count;
            }
            return config;
        }
        
        pub fn withChunkSize(self: Self, size: usize) Self {
            var config = self;
            if (@hasField(T, "performance")) {
                config.config.performance.chunk_size = size;
            }
            return config;
        }
        
        pub fn withValidation(self: Self, enabled: bool) Self {
            var config = self;
            if (@hasField(T, "validation")) {
                config.config.validation.validate_input = enabled;
            }
            return config;
        }
        
        pub fn withMonitoring(self: Self, enabled: bool) Self {
            var config = self;
            if (@hasField(T, "debug")) {
                config.config.debug.enable_monitoring = enabled;
            }
            return config;
        }
        
        pub fn build(self: Self) T {
            return self.config;
        }
    };
}

/// Get default configuration based on system capabilities
pub fn getDefaultConfig(allocator: std.mem.Allocator) BaseConfig {
    const cpu_count = std.Thread.getCpuCount() catch 1;
    
    return BaseConfig{
        .allocator = allocator,
        .performance = .{
            .thread_count = if (cpu_count > 2) cpu_count - 1 else 1,
            .enable_simd = builtin.cpu.arch.isX86() or builtin.cpu.arch.isAARCH64(),
            .enable_parallel = cpu_count > 1,
        },
    };
}

/// Configuration validation
pub fn validateConfig(config: anytype) !void {
    const T = @TypeOf(config);
    
    // Validate performance settings
    if (@hasField(T, "performance")) {
        const perf = config.performance;
        
        if (perf.chunk_size < perf.min_chunk_size) {
            return error.InvalidChunkSize;
        }
        
        if (perf.chunk_size > perf.max_chunk_size) {
            return error.InvalidChunkSize;
        }
        
        if (perf.thread_count > 1024) {
            return error.InvalidThreadCount;
        }
    }
    
    // Validate memory settings
    if (@hasField(T, "memory")) {
        const mem = config.memory;
        
        if (mem.max_buffer_size != 0 and mem.initial_buffer_size > mem.max_buffer_size) {
            return error.InvalidBufferSize;
        }
    }
    
    // Validate validation settings
    if (@hasField(T, "validation")) {
        const val = config.validation;
        
        if (val.max_depth == 0) {
            return error.InvalidMaxDepth;
        }
    }
}

// Tests
test "BaseConfig defaults" {
    const config = getDefaultConfig(std.testing.allocator);
    
    try std.testing.expect(config.performance.enable_simd);
    try std.testing.expect(config.validation.validate_input);
    try std.testing.expect(config.validation.preserve_precision);
}

test "ConfigBuilder" {
    const builder = ConfigBuilder(BaseConfig).init(std.testing.allocator);
    const config = builder
        .withOptimizationLevel(.turbo)
        .withThreadCount(8)
        .withChunkSize(128 * 1024)
        .withValidation(false)
        .withMonitoring(true)
        .build();
    
    try std.testing.expectEqual(OptimizationLevel.turbo, config.performance.optimization_level);
    try std.testing.expectEqual(@as(usize, 8), config.performance.thread_count);
    try std.testing.expectEqual(@as(usize, 128 * 1024), config.performance.chunk_size);
    try std.testing.expectEqual(false, config.validation.validate_input);
    try std.testing.expectEqual(true, config.debug.enable_monitoring);
}

test "validateConfig" {
    var config = getDefaultConfig(std.testing.allocator);
    
    // Valid config should pass
    try validateConfig(config);
    
    // Invalid chunk size should fail
    config.performance.chunk_size = 100;
    config.performance.min_chunk_size = 1024;
    try std.testing.expectError(error.InvalidChunkSize, validateConfig(config));
}