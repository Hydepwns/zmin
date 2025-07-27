const std = @import("std");

// Configuration options for parallel processing
pub const Config = struct {
    thread_count: usize = 1,
    chunk_size: usize = 64 * 1024, // 64KB default

    pub fn validate(self: Config) !void {
        if (self.chunk_size == 0) {
            return error.InvalidChunkSize;
        }
    }

    pub fn getOptimalThreadCount(self: Config) usize {
        const actual_thread_count = if (self.thread_count == 0) 1 else self.thread_count;
        const max_threads = std.Thread.getCpuCount() catch 4;
        return @min(actual_thread_count, max_threads);
    }
};

// Work item for the queue
pub const WorkItem = struct {
    chunk: []const u8,
    chunk_id: usize,
    is_final: bool,
    owns_memory: bool, // Track if this chunk owns its memory and needs freeing

    pub fn init(chunk: []const u8, chunk_id: usize, is_final: bool) WorkItem {
        return WorkItem{
            .chunk = chunk,
            .chunk_id = chunk_id,
            .is_final = is_final,
            .owns_memory = false, // Default to not owning memory (slice of original input)
        };
    }

    pub fn initOwned(chunk: []const u8, chunk_id: usize, is_final: bool) WorkItem {
        return WorkItem{
            .chunk = chunk,
            .chunk_id = chunk_id,
            .is_final = is_final,
            .owns_memory = true, // This chunk owns its memory and needs freeing
        };
    }

    pub fn deinit(self: *WorkItem, allocator: std.mem.Allocator) void {
        if (self.owns_memory) {
            allocator.free(self.chunk);
        }
    }
};

// Result from processing a chunk
pub const ChunkResult = struct {
    chunk_id: usize,
    output: []u8,

    pub fn init(chunk_id: usize, output: []u8) ChunkResult {
        return ChunkResult{
            .chunk_id = chunk_id,
            .output = output,
        };
    }

    pub fn deinit(self: *ChunkResult, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
    }
};

// Stream chunk for ordered output
pub const StreamChunk = struct {
    chunk_id: usize,
    output: []const u8,
    is_ready: bool,

    pub fn init(chunk_id: usize, output: []const u8) StreamChunk {
        return StreamChunk{
            .chunk_id = chunk_id,
            .output = output,
            .is_ready = true,
        };
    }

    pub fn deinit(self: *StreamChunk, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
    }
};

// Performance statistics
pub const PerformanceStats = struct {
    throughput_mbps: f64,
    thread_utilization: f64,
    memory_usage: usize,
    bytes_processed: u64,
    processing_time_ms: u64,

    pub fn init() PerformanceStats {
        return PerformanceStats{
            .throughput_mbps = 0.0,
            .thread_utilization = 0.0,
            .memory_usage = 0,
            .bytes_processed = 0,
            .processing_time_ms = 0,
        };
    }
};

// Error types specific to parallel processing
pub const ParallelError = error{
    ThreadPoolInitFailed,
    WorkQueueFull,
    ResultQueueFull,
    ChunkProcessingFailed,
    ThreadJoinFailed,
    InvalidConfiguration,
};
