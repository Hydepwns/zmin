// Main parallel module that exports all components
pub const config = @import("config.zig");
pub const chunk_processor = @import("chunk_processor.zig");
pub const simple_parallel_minifier = @import("simple_parallel_minifier.zig");
pub const streaming_parallel_minifier = @import("streaming_parallel_minifier.zig");

// Re-export main types for convenience
pub const Config = config.Config;
pub const WorkItem = config.WorkItem;
pub const ChunkResult = config.ChunkResult;
pub const PerformanceStats = config.PerformanceStats;
pub const ParallelError = config.ParallelError;

// Re-export component types
pub const ChunkProcessor = chunk_processor.ChunkProcessor;
pub const ParallelMinifier = streaming_parallel_minifier.StreamingParallelMinifier;
pub const StreamingParallelMinifier = streaming_parallel_minifier.StreamingParallelMinifier;
pub const SimpleParallelMinifier = simple_parallel_minifier.ParallelMinifier;

// Legacy namespace support
pub const simple = struct {
    pub const SimpleParallelMinifier = simple_parallel_minifier.ParallelMinifier;
};
