//! Unified Turbo Minifier Interface
//! 
//! This module provides a common interface for all turbo minification strategies.
//! It implements the strategy pattern to allow runtime selection of optimal
//! minification approaches based on input characteristics and system capabilities.

const std = @import("std");

/// Result of a minification operation
pub const MinificationResult = struct {
    /// Minified JSON output
    output: []u8,
    /// Size reduction ratio (0.0 to 1.0)
    compression_ratio: f64,
    /// Time taken in microseconds
    duration_us: u64,
    /// Peak memory usage in bytes
    peak_memory_bytes: u64,
    /// Strategy used for this operation
    strategy_used: StrategyType,
};

/// Available turbo strategies
pub const StrategyType = enum {
    scalar,      // CPU scalar implementation
    simd,        // SIMD optimized version
    parallel,    // Multi-threaded version
    streaming,   // Streaming for large files
    
    pub fn getDescription(self: StrategyType) []const u8 {
        return switch (self) {
            .scalar => "Single-threaded scalar processing",
            .simd => "SIMD-accelerated processing", 
            .parallel => "Multi-threaded parallel processing",
            .streaming => "Memory-efficient streaming",
        };
    }
};

/// Configuration for turbo minification
pub const TurboConfig = struct {
    /// Preferred strategy (auto-detect if null)
    strategy: ?StrategyType = null,
    /// Maximum memory usage allowed (bytes)
    max_memory_bytes: ?u64 = null,
    /// Number of threads to use (auto-detect if null)
    thread_count: ?u32 = null,
    /// Enable SIMD optimizations
    enable_simd: bool = true,
    /// Chunk size for parallel processing
    chunk_size: u32 = 1024 * 1024,
};

/// Interface that all turbo strategies must implement
pub const TurboStrategy = struct {
    const Self = @This();
    
    /// Strategy type identifier
    strategy_type: StrategyType,
    
    /// Function pointer for minification
    minifyFn: *const fn (
        self: *const Self,
        allocator: std.mem.Allocator,
        input: []const u8,
        config: TurboConfig,
    ) anyerror!MinificationResult,
    
    /// Function pointer for capability detection
    isAvailableFn: *const fn () bool,
    
    /// Function pointer for performance estimation
    estimatePerformanceFn: *const fn (input_size: u64) u64,
    
    /// Minify JSON using this strategy
    pub fn minify(
        self: *const Self,
        allocator: std.mem.Allocator,
        input: []const u8,
        config: TurboConfig,
    ) !MinificationResult {
        return self.minifyFn(self, allocator, input, config);
    }
    
    /// Check if this strategy is available on current system
    pub fn isAvailable(self: *const Self) bool {
        return self.isAvailableFn();
    }
    
    /// Estimate throughput in bytes/second for given input size
    pub fn estimatePerformance(self: *const Self, input_size: u64) u64 {
        return self.estimatePerformanceFn(input_size);
    }
};

/// Error types specific to turbo minification
pub const TurboError = error{
    /// Input too large for available memory
    InputTooLarge,
    /// Strategy not available on this system
    StrategyUnavailable,
    /// Performance threshold not met
    PerformanceThresholdNotMet,
    /// SIMD not supported but required
    SimdUnsupported,
    /// Insufficient threads available
    InsufficientThreads,
    /// Memory allocation failed
    OutOfMemory,
    /// Invalid JSON input
    InvalidJson,
};

/// System capabilities detection
pub const SystemCapabilities = struct {
    /// Number of logical CPU cores
    cpu_cores: u32,
    /// Available memory in bytes
    available_memory: u64,
    /// SIMD instruction sets available
    simd_features: SimdFeatures,
    /// NUMA topology information
    numa_nodes: u32,
    
    /// Detect current system capabilities
    pub fn detect() !SystemCapabilities {
        return SystemCapabilities{
            .cpu_cores = std.Thread.getCpuCount() catch 1,
            .available_memory = detectAvailableMemory(),
            .simd_features = detectSimdFeatures(),
            .numa_nodes = detectNumaNodes(),
        };
    }
    
    fn detectAvailableMemory() u64 {
        // TODO: Implement platform-specific memory detection
        return 8 * 1024 * 1024 * 1024; // Default 8GB
    }
    
    fn detectSimdFeatures() SimdFeatures {
        // TODO: Implement SIMD feature detection
        return SimdFeatures{};
    }
    
    fn detectNumaNodes() u32 {
        // TODO: Implement NUMA detection
        return 1;
    }
};

/// SIMD instruction set capabilities
pub const SimdFeatures = struct {
    sse: bool = false,
    sse2: bool = false,
    sse3: bool = false,
    ssse3: bool = false,
    sse4_1: bool = false,
    sse4_2: bool = false,
    avx: bool = false,
    avx2: bool = false,
    avx512: bool = false,
};