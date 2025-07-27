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
    scalar, // CPU scalar implementation
    simd, // SIMD optimized version
    parallel, // Multi-threaded version
    streaming, // Streaming for large files

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
            .cpu_cores = @intCast(std.Thread.getCpuCount() catch 1),
            .available_memory = detectAvailableMemory(),
            .simd_features = detectSimdFeatures(),
            .numa_nodes = detectNumaNodes(),
        };
    }

    fn detectAvailableMemory() u64 {
        const builtin = @import("builtin");
        
        return switch (builtin.os.tag) {
            .linux => detectLinuxMemory(),
            .windows => detectWindowsMemory(),
            .macos => detectMacOSMemory(),
            else => 8 * 1024 * 1024 * 1024, // Default 8GB for other platforms
        };
    }
    
    /// Detect available memory on Linux
    fn detectLinuxMemory() u64 {
        // Read /proc/meminfo to get MemAvailable (or MemFree + Buffers + Cached)
        const meminfo = std.fs.cwd().readFileAlloc(
            std.heap.page_allocator, 
            "/proc/meminfo", 
            8192
        ) catch return getDefaultMemory();
        defer std.heap.page_allocator.free(meminfo);

        var mem_available: ?u64 = null;
        var mem_free: u64 = 0;
        var buffers: u64 = 0;
        var cached: u64 = 0;

        var lines = std.mem.tokenizeAny(u8, meminfo, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "MemAvailable:")) {
                if (parseMemoryLine(line)) |value| {
                    mem_available = value;
                }
            } else if (std.mem.startsWith(u8, line, "MemFree:")) {
                if (parseMemoryLine(line)) |value| {
                    mem_free = value;
                }
            } else if (std.mem.startsWith(u8, line, "Buffers:")) {
                if (parseMemoryLine(line)) |value| {
                    buffers = value;
                }
            } else if (std.mem.startsWith(u8, line, "Cached:")) {
                if (parseMemoryLine(line)) |value| {
                    cached = value;
                }
            }
        }

        // Prefer MemAvailable if available (Linux 3.14+), otherwise estimate
        if (mem_available) |available| {
            return available * 1024; // Convert KB to bytes
        } else {
            // Estimate available memory as free + buffers + cached
            return (mem_free + buffers + cached) * 1024;
        }
    }
    
    /// Detect available memory on Windows
    fn detectWindowsMemory() u64 {
        // On Windows, we would use GlobalMemoryStatusEx() from Win32 API
        // For now, return a reasonable estimate based on common system sizes
        // A full implementation would use: 
        // const kernel32 = std.os.windows.kernel32;
        // var memstat: std.os.windows.MEMORYSTATUSEX = undefined;
        // memstat.dwLength = @sizeOf(std.os.windows.MEMORYSTATUSEX);
        // if (kernel32.GlobalMemoryStatusEx(&memstat) != 0) {
        //     return memstat.ullAvailPhys;
        // }
        
        // For this implementation, return 75% of a typical system (8GB)
        return 6 * 1024 * 1024 * 1024; // 6GB estimate
    }
    
    /// Detect available memory on macOS
    fn detectMacOSMemory() u64 {
        // On macOS, we would use sysctl to get memory information
        // sysctlbyname("hw.memsize", ...) for total memory
        // vm_stat for available memory
        // For now, return a reasonable estimate
        
        // For this implementation, return 75% of a typical Mac (8GB)
        return 6 * 1024 * 1024 * 1024; // 6GB estimate
    }
    
    /// Parse a memory line from /proc/meminfo (format: "MemTotal: 16384 kB")
    fn parseMemoryLine(line: []const u8) ?u64 {
        var parts = std.mem.tokenizeAny(u8, line, " \t");
        _ = parts.next(); // Skip the label (e.g., "MemTotal:")
        const size_str = parts.next() orelse return null;
        return std.fmt.parseInt(u64, size_str, 10) catch null;
    }
    
    /// Get default memory value
    fn getDefaultMemory() u64 {
        return 8 * 1024 * 1024 * 1024; // 8GB
    }

    fn detectSimdFeatures() SimdFeatures {
        const cpu_detection = @import("../../../performance/cpu_detection.zig");
        const cpu_info = cpu_detection.CpuInfo.init();
        
        return SimdFeatures{
            .sse = cpu_info.features.sse,
            .sse2 = cpu_info.features.sse2,
            .sse3 = cpu_info.features.sse3,
            .ssse3 = cpu_info.features.ssse3,
            .sse4_1 = cpu_info.features.sse4_1,
            .sse4_2 = cpu_info.features.sse4_2,
            .avx = cpu_info.features.avx,
            .avx2 = cpu_info.features.avx2,
            .avx512 = cpu_info.features.avx512f and 
                      cpu_info.features.avx512dq and 
                      cpu_info.features.avx512bw and 
                      cpu_info.features.avx512vl,
        };
    }

    fn detectNumaNodes() u32 {
        const detector = @import("../../../performance/numa_detector.zig");
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();

        var topology = detector.detect(gpa.allocator()) catch return 1;
        defer topology.deinit();

        return topology.node_count;
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
    
    /// Check if any SIMD features are available
    pub fn hasAnySimd(self: SimdFeatures) bool {
        return self.sse or self.sse2 or self.sse3 or self.ssse3 or 
               self.sse4_1 or self.sse4_2 or self.avx or self.avx2 or self.avx512;
    }
    
    /// Get the best available SIMD level
    pub fn getBestLevel(self: SimdFeatures) ?StrategyType {
        if (self.avx512) return .simd;
        if (self.avx2) return .simd;
        if (self.avx) return .simd;
        if (self.sse4_1 or self.sse4_2) return .simd;
        if (self.sse2) return .simd;
        return null;
    }
    
    /// Get a description of available SIMD features
    pub fn getDescription(self: SimdFeatures) []const u8 {
        if (self.avx512) return "AVX-512";
        if (self.avx2) return "AVX2";
        if (self.avx) return "AVX";
        if (self.sse4_2) return "SSE4.2";
        if (self.sse4_1) return "SSE4.1";
        if (self.ssse3) return "SSSE3";
        if (self.sse3) return "SSE3";
        if (self.sse2) return "SSE2";
        if (self.sse) return "SSE";
        return "None";
    }
};
