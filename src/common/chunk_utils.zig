//! Chunk Size Calculation Utilities
//!
//! This module consolidates all chunk size calculation logic to ensure
//! consistent chunking strategies across the codebase.

const std = @import("std");
const constants = @import("constants.zig");
const simd_detector = @import("../platform/simd_detector.zig");

/// Chunk size recommendation
pub const ChunkRecommendation = struct {
    /// Recommended chunk size
    size: usize,
    
    /// Number of chunks
    count: usize,
    
    /// Alignment requirement
    alignment: usize,
    
    /// Rationale for the recommendation
    rationale: []const u8,
};

/// Calculate optimal chunk size based on multiple factors
pub fn calculateOptimalChunkSize(params: ChunkParams) ChunkRecommendation {
    // Start with basic size categorization
    const category = constants.FileSize.categorize(params.data_size);
    var base_size = category.getOptimalChunkSize();
    
    // Adjust for CPU features
    if (params.cpu_features) |features| {
        const vector_size = features.getBestSimdLevel().getVectorSize();
        base_size = alignToVector(base_size, vector_size);
        
        // Consider cache sizes
        if (base_size > features.l2_cache / 4) {
            base_size = alignToVector(features.l2_cache / 4, vector_size);
        }
    }
    
    // Adjust for thread count
    if (params.thread_count > 1) {
        const min_chunks = params.thread_count * 4; // At least 4 chunks per thread
        const max_chunk_size = params.data_size / min_chunks;
        base_size = @min(base_size, max_chunk_size);
    }
    
    // Apply constraints
    base_size = @max(base_size, params.min_chunk_size);
    base_size = @min(base_size, params.max_chunk_size);
    
    // Calculate final chunk count
    const chunk_count = (params.data_size + base_size - 1) / base_size;
    
    // Determine alignment
    const alignment = if (params.cpu_features) |features|
        features.getBestSimdLevel().getVectorSize()
    else
        constants.System.CACHE_LINE_SIZE;
    
    // Generate rationale
    const rationale = getRationale(category, params);
    
    return ChunkRecommendation{
        .size = base_size,
        .count = chunk_count,
        .alignment = alignment,
        .rationale = rationale,
    };
}

/// Parameters for chunk size calculation
pub const ChunkParams = struct {
    /// Size of data to process
    data_size: usize,
    
    /// Number of threads available
    thread_count: usize = 1,
    
    /// CPU features (optional)
    cpu_features: ?simd_detector.CpuFeatures = null,
    
    /// Minimum allowed chunk size
    min_chunk_size: usize = constants.Chunk.MIN_SIZE,
    
    /// Maximum allowed chunk size
    max_chunk_size: usize = constants.Chunk.XLARGE,
    
    /// Processing pattern
    pattern: ProcessingPattern = .sequential,
    
    /// Memory constraints
    memory_limit: usize = 0,
};

/// Processing patterns that affect chunking
pub const ProcessingPattern = enum {
    /// Sequential processing
    sequential,
    
    /// Parallel processing
    parallel,
    
    /// Streaming (one chunk at a time)
    streaming,
    
    /// Random access
    random_access,
};

/// Align chunk size to vector boundary
fn alignToVector(size: usize, vector_size: usize) usize {
    return (size + vector_size - 1) / vector_size * vector_size;
}

/// Generate rationale for chunk size selection
fn getRationale(category: constants.FileSize, params: ChunkParams) []const u8 {
    return switch (category) {
        .tiny => "Tiny file: single chunk for minimal overhead",
        .small => "Small file: optimized for L1 cache",
        .medium => "Medium file: balanced for L2 cache",
        .large => if (params.thread_count > 1)
            "Large file: sized for parallel processing"
        else
            "Large file: sized for L3 cache",
        .huge => "Huge file: optimized for memory bandwidth",
    };
}

/// Adaptive chunk size calculator that adjusts based on performance
pub const AdaptiveChunker = struct {
    /// Base parameters
    params: ChunkParams,
    
    /// Performance history
    history: std.ArrayList(PerformanceSample),
    
    /// Current chunk size
    current_size: usize,
    
    /// Allocator
    allocator: std.mem.Allocator,
    
    const PerformanceSample = struct {
        chunk_size: usize,
        throughput_mbps: f64,
        timestamp: i64,
    };
    
    pub fn init(allocator: std.mem.Allocator, params: ChunkParams) AdaptiveChunker {
        const initial = calculateOptimalChunkSize(params);
        return .{
            .params = params,
            .history = std.ArrayList(PerformanceSample).init(allocator),
            .current_size = initial.size,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *AdaptiveChunker) void {
        self.history.deinit();
    }
    
    /// Record performance sample
    pub fn recordSample(self: *AdaptiveChunker, throughput_mbps: f64) !void {
        try self.history.append(.{
            .chunk_size = self.current_size,
            .throughput_mbps = throughput_mbps,
            .timestamp = std.time.timestamp(),
        });
        
        // Adjust chunk size based on performance
        if (self.history.items.len >= 3) {
            self.adjustChunkSize();
        }
    }
    
    /// Adjust chunk size based on performance history
    fn adjustChunkSize(self: *AdaptiveChunker) void {
        // Simple hill climbing algorithm
        const recent = self.history.items[self.history.items.len - 3..];
        
        var improving = true;
        for (1..recent.len) |i| {
            if (recent[i].throughput_mbps <= recent[i-1].throughput_mbps * 1.05) {
                improving = false;
                break;
            }
        }
        
        if (improving) {
            // Continue in the same direction
            if (recent[2].chunk_size > recent[0].chunk_size) {
                self.current_size = @min(self.current_size * 2, self.params.max_chunk_size);
            } else {
                self.current_size = @max(self.current_size / 2, self.params.min_chunk_size);
            }
        } else {
            // Try the opposite direction
            if (recent[2].chunk_size > recent[0].chunk_size) {
                self.current_size = @max(self.current_size / 2, self.params.min_chunk_size);
            } else {
                self.current_size = @min(self.current_size * 2, self.params.max_chunk_size);
            }
        }
        
        // Align to cache line
        self.current_size = alignToVector(self.current_size, constants.System.CACHE_LINE_SIZE);
    }
    
    /// Get current chunk size
    pub fn getChunkSize(self: *AdaptiveChunker) usize {
        return self.current_size;
    }
    
    /// Get performance summary
    pub fn getSummary(self: *AdaptiveChunker) ChunkingSummary {
        if (self.history.items.len == 0) {
            return .{
                .best_chunk_size = self.current_size,
                .best_throughput = 0,
                .samples_collected = 0,
            };
        }
        
        var best_throughput: f64 = 0;
        var best_size: usize = self.current_size;
        
        for (self.history.items) |sample| {
            if (sample.throughput_mbps > best_throughput) {
                best_throughput = sample.throughput_mbps;
                best_size = sample.chunk_size;
            }
        }
        
        return .{
            .best_chunk_size = best_size,
            .best_throughput = best_throughput,
            .samples_collected = self.history.items.len,
        };
    }
};

/// Summary of chunking performance
pub const ChunkingSummary = struct {
    best_chunk_size: usize,
    best_throughput: f64,
    samples_collected: usize,
};

/// Calculate chunk boundaries for parallel processing
pub fn calculateChunkBoundaries(
    data_size: usize,
    chunk_size: usize,
    overlap: usize,
) ![]ChunkBoundary {
    var boundaries = std.ArrayList(ChunkBoundary).init(std.heap.page_allocator);
    errdefer boundaries.deinit();
    
    var offset: usize = 0;
    while (offset < data_size) {
        const end = @min(offset + chunk_size, data_size);
        const overlap_end = @min(end + overlap, data_size);
        
        try boundaries.append(.{
            .start = offset,
            .end = end,
            .overlap_end = overlap_end,
        });
        
        offset = end;
    }
    
    return boundaries.toOwnedSlice();
}

/// Chunk boundary information
pub const ChunkBoundary = struct {
    /// Start offset (inclusive)
    start: usize,
    
    /// End offset (exclusive)
    end: usize,
    
    /// End offset including overlap (exclusive)
    overlap_end: usize,
    
    /// Get chunk size
    pub fn size(self: ChunkBoundary) usize {
        return self.end - self.start;
    }
    
    /// Get total size including overlap
    pub fn totalSize(self: ChunkBoundary) usize {
        return self.overlap_end - self.start;
    }
};

/// Work distribution for parallel processing
pub fn distributeWork(
    total_items: usize,
    worker_count: usize,
) []WorkAssignment {
    var assignments = std.ArrayList(WorkAssignment).init(std.heap.page_allocator) catch {
        return &[_]WorkAssignment{};
    };
    defer assignments.deinit();
    
    const items_per_worker = total_items / worker_count;
    const remainder = total_items % worker_count;
    
    var offset: usize = 0;
    for (0..worker_count) |i| {
        const extra = if (i < remainder) @as(usize, 1) else 0;
        const count = items_per_worker + extra;
        
        assignments.append(.{
            .worker_id = i,
            .start_index = offset,
            .item_count = count,
        }) catch break;
        
        offset += count;
    }
    
    return assignments.toOwnedSlice() catch &[_]WorkAssignment{};
}

/// Work assignment for a worker
pub const WorkAssignment = struct {
    worker_id: usize,
    start_index: usize,
    item_count: usize,
};

// Tests
test "calculateOptimalChunkSize basic" {
    const params = ChunkParams{
        .data_size = 10 * 1024 * 1024, // 10MB
        .thread_count = 4,
    };
    
    const result = calculateOptimalChunkSize(params);
    
    try std.testing.expect(result.size >= constants.Chunk.MIN_SIZE);
    try std.testing.expect(result.size <= constants.Chunk.XLARGE);
    try std.testing.expect(result.count >= 4); // At least one per thread
}

test "AdaptiveChunker" {
    var chunker = AdaptiveChunker.init(std.testing.allocator, .{
        .data_size = 100 * 1024 * 1024,
    });
    defer chunker.deinit();
    
    // Record some samples
    try chunker.recordSample(1000.0);
    try chunker.recordSample(1100.0);
    try chunker.recordSample(1200.0);
    
    const summary = chunker.getSummary();
    try std.testing.expectEqual(@as(f64, 1200.0), summary.best_throughput);
}

test "calculateChunkBoundaries" {
    const boundaries = try calculateChunkBoundaries(1000, 300, 50);
    defer std.heap.page_allocator.free(boundaries);
    
    try std.testing.expectEqual(@as(usize, 4), boundaries.len);
    
    // Check first chunk
    try std.testing.expectEqual(@as(usize, 0), boundaries[0].start);
    try std.testing.expectEqual(@as(usize, 300), boundaries[0].end);
    try std.testing.expectEqual(@as(usize, 350), boundaries[0].overlap_end);
    
    // Check last chunk
    try std.testing.expectEqual(@as(usize, 900), boundaries[3].start);
    try std.testing.expectEqual(@as(usize, 1000), boundaries[3].end);
    try std.testing.expectEqual(@as(usize, 1000), boundaries[3].overlap_end);
}