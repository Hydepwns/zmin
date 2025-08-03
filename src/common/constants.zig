//! Common Constants and Magic Numbers
//!
//! This module centralizes all magic numbers and constants used throughout
//! the codebase to ensure consistency and ease of maintenance.

const std = @import("std");

/// System-level constants
pub const System = struct {
    /// CPU cache line size (bytes)
    pub const CACHE_LINE_SIZE: usize = 64;
    
    /// Memory page size (typical)
    pub const PAGE_SIZE: usize = 4096;
    
    /// Huge page size (2MB)
    pub const HUGE_PAGE_SIZE: usize = 2 * 1024 * 1024;
    
    /// Maximum path length
    pub const MAX_PATH_LEN: usize = 4096;
};

/// CPU cache hierarchy sizes
pub const Cache = struct {
    /// Typical L1 data cache size
    pub const L1_DATA_SIZE: usize = 32 * 1024;
    
    /// Typical L1 instruction cache size
    pub const L1_INST_SIZE: usize = 32 * 1024;
    
    /// Typical L2 cache size
    pub const L2_SIZE: usize = 256 * 1024;
    
    /// Typical L3 cache size
    pub const L3_SIZE: usize = 8 * 1024 * 1024;
    
    /// Apple Silicon cache sizes
    pub const AppleSilicon = struct {
        pub const L1_DATA_SIZE: usize = 128 * 1024;
        pub const L1_INST_SIZE: usize = 192 * 1024;
        pub const L2_SIZE: usize = 4 * 1024 * 1024;
    };
};

/// Buffer sizes used throughout the system
pub const Buffer = struct {
    /// Minimum buffer size
    pub const MIN_SIZE: usize = 1024;
    
    /// Small buffer (16KB)
    pub const SMALL: usize = 16 * 1024;
    
    /// Medium buffer (64KB)
    pub const MEDIUM: usize = 64 * 1024;
    
    /// Large buffer (256KB)
    pub const LARGE: usize = 256 * 1024;
    
    /// Extra large buffer (1MB)
    pub const XLARGE: usize = 1024 * 1024;
    
    /// Huge buffer (4MB)
    pub const HUGE: usize = 4 * 1024 * 1024;
    
    /// Default buffer size
    pub const DEFAULT: usize = MEDIUM;
    
    /// Streaming buffer size
    pub const STREAMING: usize = 8 * 1024;
    
    /// Stack buffer size limit
    pub const STACK_LIMIT: usize = 8 * 1024;
};

/// Chunk sizes for parallel processing
pub const Chunk = struct {
    /// Minimum chunk size
    pub const MIN_SIZE: usize = 1024;
    
    /// Small chunk (16KB)
    pub const SMALL: usize = 16 * 1024;
    
    /// Medium chunk (64KB)
    pub const MEDIUM: usize = 64 * 1024;
    
    /// Large chunk (256KB)
    pub const LARGE: usize = 256 * 1024;
    
    /// Extra large chunk (1MB)
    pub const XLARGE: usize = 1024 * 1024;
    
    /// Default chunk size
    pub const DEFAULT: usize = MEDIUM;
    
    /// Get optimal chunk size based on data size
    pub fn getOptimal(data_size: usize) usize {
        if (data_size < 10 * SMALL) return SMALL;
        if (data_size < 10 * MEDIUM) return MEDIUM;
        if (data_size < 10 * LARGE) return LARGE;
        return XLARGE;
    }
};

/// SIMD vector sizes
pub const Simd = struct {
    /// SSE register size (128 bits / 16 bytes)
    pub const SSE_SIZE: usize = 16;
    
    /// AVX register size (256 bits / 32 bytes)
    pub const AVX_SIZE: usize = 32;
    
    /// AVX-512 register size (512 bits / 64 bytes)
    pub const AVX512_SIZE: usize = 64;
    
    /// ARM NEON register size (128 bits / 16 bytes)
    pub const NEON_SIZE: usize = 16;
    
    /// Maximum vector size we support
    pub const MAX_VECTOR_SIZE: usize = AVX512_SIZE;
};

/// JSON processing limits
pub const Json = struct {
    /// Maximum nesting depth
    pub const MAX_DEPTH: u32 = 1000;
    
    /// Maximum string length
    pub const MAX_STRING_LEN: usize = 1024 * 1024 * 1024; // 1GB
    
    /// Maximum array/object size
    pub const MAX_CONTAINER_SIZE: usize = 10_000_000;
    
    /// Stack buffer for small strings
    pub const SMALL_STRING_SIZE: usize = 256;
    
    /// Unicode escape buffer size
    pub const UNICODE_BUFFER_SIZE: usize = 12; // "\uXXXX\uXXXX"
};

/// Performance thresholds
pub const Performance = struct {
    /// Target throughput (MB/s)
    pub const TARGET_THROUGHPUT_MBPS: f64 = 5000.0; // 5 GB/s
    
    /// Minimum acceptable throughput (MB/s)
    pub const MIN_THROUGHPUT_MBPS: f64 = 1000.0; // 1 GB/s
    
    /// Maximum acceptable latency (ms)
    pub const MAX_LATENCY_MS: u32 = 100;
    
    /// Benchmark warmup iterations
    pub const WARMUP_ITERATIONS: usize = 10;
    
    /// Benchmark measurement iterations
    pub const MEASURE_ITERATIONS: usize = 100;
};

/// Thread pool configuration
pub const ThreadPool = struct {
    /// Default thread count (0 = auto-detect)
    pub const DEFAULT_THREADS: usize = 0;
    
    /// Maximum thread count
    pub const MAX_THREADS: usize = 256;
    
    /// Worker thread stack size
    pub const WORKER_STACK_SIZE: usize = 8 * 1024 * 1024;
    
    /// Work queue size
    pub const QUEUE_SIZE: usize = 1000;
    
    /// Work stealing attempts
    pub const STEAL_ATTEMPTS: u32 = 3;
};

/// Memory limits and thresholds
pub const Memory = struct {
    /// ECO mode memory limit
    pub const ECO_MODE_LIMIT: usize = 10 * 1024 * 1024; // 10MB
    
    /// Swap threshold for large files
    pub const SWAP_THRESHOLD: usize = 100 * 1024 * 1024; // 100MB
    
    /// Arena allocator chunk size
    pub const ARENA_CHUNK_SIZE: usize = 1024 * 1024; // 1MB
    
    /// Pool allocator bucket sizes
    pub const POOL_BUCKETS: [8]usize = .{
        64, 128, 256, 512, 1024, 2048, 4096, 8192
    };
};

/// Timing constants
pub const Time = struct {
    /// Nanoseconds per second
    pub const NS_PER_SECOND: u64 = 1_000_000_000;
    
    /// Nanoseconds per millisecond
    pub const NS_PER_MS: u64 = 1_000_000;
    
    /// Nanoseconds per microsecond
    pub const NS_PER_US: u64 = 1_000;
    
    /// Default timeout (ms)
    pub const DEFAULT_TIMEOUT_MS: u32 = 5000;
};

/// File size categories
pub const FileSize = enum {
    tiny,     // < 1KB
    small,    // < 64KB
    medium,   // < 1MB
    large,    // < 10MB
    huge,     // >= 10MB
    
    pub fn categorize(size: usize) FileSize {
        if (size < 1024) return .tiny;
        if (size < 64 * 1024) return .small;
        if (size < 1024 * 1024) return .medium;
        if (size < 10 * 1024 * 1024) return .large;
        return .huge;
    }
    
    pub fn getOptimalChunkSize(self: FileSize) usize {
        return switch (self) {
            .tiny => Chunk.MIN_SIZE,
            .small => Chunk.SMALL,
            .medium => Chunk.MEDIUM,
            .large => Chunk.LARGE,
            .huge => Chunk.XLARGE,
        };
    }
    
    pub fn getOptimalThreadCount(self: FileSize) usize {
        return switch (self) {
            .tiny, .small => 1,
            .medium => 2,
            .large => 4,
            .huge => 0, // auto-detect
        };
    }
};

/// Format helpers
pub const Format = struct {
    /// Format bytes as human-readable string
    pub fn bytes(size: usize) []const u8 {
        if (size < 1024) return std.fmt.allocPrint(std.heap.page_allocator, "{} B", .{size}) catch "? B";
        if (size < 1024 * 1024) return std.fmt.allocPrint(std.heap.page_allocator, "{d:.2} KB", .{@as(f64, @floatFromInt(size)) / 1024.0}) catch "? KB";
        if (size < 1024 * 1024 * 1024) return std.fmt.allocPrint(std.heap.page_allocator, "{d:.2} MB", .{@as(f64, @floatFromInt(size)) / (1024.0 * 1024.0)}) catch "? MB";
        return std.fmt.allocPrint(std.heap.page_allocator, "{d:.2} GB", .{@as(f64, @floatFromInt(size)) / (1024.0 * 1024.0 * 1024.0)}) catch "? GB";
    }
    
    /// Format throughput as MB/s
    pub fn throughput(bytes_per_second: f64) []const u8 {
        const mbps = bytes_per_second / (1024.0 * 1024.0);
        return std.fmt.allocPrint(std.heap.page_allocator, "{d:.2} MB/s", .{mbps}) catch "? MB/s";
    }
};

// Tests
test "FileSize categorization" {
    const testing = std.testing;
    
    try testing.expectEqual(FileSize.tiny, FileSize.categorize(512));
    try testing.expectEqual(FileSize.small, FileSize.categorize(32 * 1024));
    try testing.expectEqual(FileSize.medium, FileSize.categorize(512 * 1024));
    try testing.expectEqual(FileSize.large, FileSize.categorize(5 * 1024 * 1024));
    try testing.expectEqual(FileSize.huge, FileSize.categorize(20 * 1024 * 1024));
}

test "Chunk size selection" {
    const testing = std.testing;
    
    try testing.expectEqual(Chunk.SMALL, Chunk.getOptimal(100 * 1024));
    try testing.expectEqual(Chunk.MEDIUM, Chunk.getOptimal(500 * 1024));
    try testing.expectEqual(Chunk.LARGE, Chunk.getOptimal(2 * 1024 * 1024));
    try testing.expectEqual(Chunk.XLARGE, Chunk.getOptimal(10 * 1024 * 1024));
}