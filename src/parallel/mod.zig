// Main parallel module that exports all components
pub const config = @import("config.zig");
pub const thread_pool = @import("thread_pool.zig");
pub const work_queue = @import("work_queue.zig");
pub const result_queue = @import("result_queue.zig");
pub const chunk_processor = @import("chunk_processor.zig");
pub const minifier = @import("minifier.zig");
pub const simple = @import("simple.zig");

// Re-export main types for convenience
pub const ParallelMinifier = minifier.ParallelMinifier;
pub const SimpleParallelMinifier = simple.SimpleParallelMinifier;
pub const Config = config.Config;
pub const WorkItem = config.WorkItem;
pub const ChunkResult = config.ChunkResult;
pub const PerformanceStats = config.PerformanceStats;
pub const ParallelError = config.ParallelError;

// Re-export component types
pub const ThreadPool = thread_pool.ThreadPool;
pub const WorkQueue = work_queue.WorkQueue;
pub const ResultQueue = result_queue.ResultQueue;
pub const ChunkProcessor = chunk_processor.ChunkProcessor;
