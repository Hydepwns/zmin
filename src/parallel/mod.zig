// Main parallel module that exports all components
pub const config = @import("config.zig");
pub const thread_pool = @import("thread_pool.zig");
pub const work_queue = @import("work_queue.zig");
pub const result_queue = @import("result_queue.zig");
pub const chunk_processor = @import("chunk_processor.zig");
pub const minifier = @import("minifier.zig");
pub const simple = @import("simple.zig");

// Phase 2: Advanced Parallel Processing components
pub const work_stealing_pool = @import("work_stealing_pool.zig");
pub const numa_processor = @import("numa_processor.zig");
pub const lock_free_queue = @import("lock_free_queue.zig");
pub const adaptive_chunker = @import("adaptive_chunker.zig");
pub const enhanced_minifier = @import("enhanced_minifier.zig");

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

// Re-export Phase 2 types
pub const WorkStealingThreadPool = work_stealing_pool.WorkStealingThreadPool;
pub const WorkStealingQueue = work_stealing_pool.WorkStealingQueue;
pub const NumaProcessor = numa_processor.NumaProcessor;
pub const NumaNode = numa_processor.NumaNode;
pub const NumaWorkDistributor = numa_processor.NumaWorkDistributor;
pub const LockFreeQueue = lock_free_queue.LockFreeQueue;
pub const LockFreeRingBuffer = lock_free_queue.LockFreeRingBuffer;
pub const LockFreeStack = lock_free_queue.LockFreeStack;
pub const AdaptiveChunker = adaptive_chunker.AdaptiveChunker;
pub const ChunkStatistics = adaptive_chunker.ChunkStatistics;
pub const EnhancedParallelMinifier = enhanced_minifier.EnhancedParallelMinifier;
pub const EnhancedChunkProcessor = enhanced_minifier.EnhancedChunkProcessor;
pub const Phase2PerformanceMonitor = enhanced_minifier.Phase2PerformanceMonitor;
