const std = @import("std");
const Allocator = std.mem.Allocator;
const StreamingParser = @import("parser.zig").StreamingParser;
const ParserConfig = @import("parser.zig").ParserConfig;
const Token = @import("parser.zig").Token;
const TokenType = @import("parser.zig").TokenType;
const SimdLevel = @import("parser.zig").SimdLevel;

/// Configuration for parallel JSON parsing
pub const ParallelConfig = struct {
    /// Number of worker threads (0 = auto-detect CPU cores)
    num_threads: usize = 0,
    
    /// Minimum chunk size for parallel processing (default: 1MB)
    min_chunk_size: usize = 1024 * 1024,
    
    /// Target chunk size for work distribution (default: 4MB)
    target_chunk_size: usize = 4 * 1024 * 1024,
    
    /// Parser configuration for individual workers
    parser_config: ParserConfig = .{},
    
    /// Enable work stealing between threads
    enable_work_stealing: bool = true,
    
    /// Enable adaptive chunk sizing based on performance
    enable_adaptive_chunking: bool = true,
    
    /// Buffer size for token stream merging
    merge_buffer_size: usize = 1024 * 1024,
};

/// Represents a chunk of JSON data for parallel processing
pub const JsonChunk = struct {
    /// Start position in the input data
    start: usize,
    
    /// End position in the input data (exclusive)
    end: usize,
    
    /// Depth level at chunk start (for context)
    start_depth: i32,
    
    /// Type of JSON structure at chunk boundary
    boundary_type: BoundaryType,
    
    /// Whether this chunk is complete (can be parsed independently)
    is_complete: bool,
};

/// Type of JSON structure at chunk boundary
pub const BoundaryType = enum {
    none,
    object,
    array,
    string,
    number,
    literal,
};

/// Result from processing a chunk
pub const ChunkResult = struct {
    /// Tokens parsed from this chunk
    tokens: std.ArrayList(Token),
    
    /// Start position in original input
    start_pos: usize,
    
    /// End position in original input
    end_pos: usize,
    
    /// Depth level at end of chunk
    end_depth: i32,
    
    /// Processing time in nanoseconds
    processing_time: u64,
    
    /// Any error encountered
    err: ?ParallelError = null,
};

/// Errors specific to parallel parsing
pub const ParallelError = error{
    ChunkBoundaryError,
    TokenMergeError,
    WorkerThreadError,
    SynchronizationError,
    InvalidChunkSize,
};

/// Work item for thread pool
const WorkItem = struct {
    chunk: JsonChunk,
    data: []const u8,
    id: usize,
};

/// Thread pool for parallel execution
const ThreadPool = struct {
    const Self = @This();
    
    threads: []std.Thread,
    work_queue: WorkQueue,
    results: ResultCollector,
    config: ParallelConfig,
    should_stop: std.atomic.Value(bool),
    active_workers: std.atomic.Value(usize),
    
    fn init(allocator: Allocator, config: ParallelConfig) !Self {
        const num_threads = if (config.num_threads > 0) 
            config.num_threads 
        else 
            try std.Thread.getCpuCount();
        
        const threads = try allocator.alloc(std.Thread, num_threads);
        errdefer allocator.free(threads);
        
        return Self{
            .threads = threads,
            .work_queue = try WorkQueue.init(allocator, num_threads * 4),
            .results = try ResultCollector.init(allocator),
            .config = config,
            .should_stop = std.atomic.Value(bool).init(false),
            .active_workers = std.atomic.Value(usize).init(0),
        };
    }
    
    fn deinit(self: *Self, allocator: Allocator) void {
        self.work_queue.deinit();
        self.results.deinit();
        allocator.free(self.threads);
    }
    
    fn start(self: *Self, allocator: Allocator) !void {
        for (self.threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerWrapper, .{ self, allocator, i });
        }
    }
    
    fn stop(self: *Self) void {
        self.should_stop.store(true, .release);
        self.work_queue.shutdown();
        
        for (self.threads) |thread| {
            thread.join();
        }
    }
    
    fn workerWrapper(self: *Self, allocator: Allocator, worker_id: usize) void {
        self.worker(allocator, worker_id) catch {};
    }
    
    fn worker(self: *Self, allocator: Allocator, worker_id: usize) !void {
        _ = worker_id;
        _ = self.active_workers.fetchAdd(1, .acq_rel);
        defer _ = self.active_workers.fetchSub(1, .acq_rel);
        
        var parser = StreamingParser.init(allocator, self.config.parser_config) catch return;
        defer parser.deinit();
        
        while (!self.should_stop.load(.acquire)) {
            const work_item = self.work_queue.dequeue() orelse {
                if (self.config.enable_work_stealing) {
                    // Try to steal work from other queues
                    std.time.sleep(1000); // 1μs
                    continue;
                }
                std.time.sleep(10000); // 10μs
                continue;
            };
            
            const start_time = std.time.nanoTimestamp();
            
            var tokens = std.ArrayList(Token).init(allocator);
            const chunk_data = work_item.data[work_item.chunk.start..work_item.chunk.end];
            
            // Parse the chunk using streaming API
            var token_stream = parser.parseStreaming(chunk_data) catch {
                self.results.addResult(ChunkResult{
                    .tokens = tokens,
                    .start_pos = work_item.chunk.start,
                    .end_pos = work_item.chunk.end,
                    .end_depth = work_item.chunk.start_depth,
                    .processing_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time)),
                    .err = ParallelError.WorkerThreadError,
                });
                continue;
            };
            defer token_stream.deinit();
            
            // Copy tokens from stream
            while (token_stream.hasMore()) {
                if (token_stream.getCurrentToken()) |token| {
                    try tokens.append(token);
                }
                token_stream.advance();
            }
            
            const processing_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
            
            self.results.addResult(ChunkResult{
                .tokens = tokens,
                .start_pos = work_item.chunk.start,
                .end_pos = work_item.chunk.end,
                .end_depth = work_item.chunk.start_depth, // TODO: Calculate actual end depth
                .processing_time = processing_time,
            });
        }
    }
};

/// Work queue for distributing chunks
const WorkQueue = struct {
    const Self = @This();
    
    items: std.ArrayList(WorkItem),
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    is_shutdown: bool,
    
    fn init(allocator: Allocator, capacity: usize) !Self {
        return Self{
            .items = try std.ArrayList(WorkItem).initCapacity(allocator, capacity),
            .mutex = .{},
            .condition = .{},
            .is_shutdown = false,
        };
    }
    
    fn deinit(self: *Self) void {
        self.items.deinit();
    }
    
    fn enqueue(self: *Self, item: WorkItem) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.items.append(item);
        self.condition.signal();
    }
    
    fn dequeue(self: *Self) ?WorkItem {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        while (self.items.items.len == 0 and !self.is_shutdown) {
            self.condition.wait(&self.mutex);
        }
        
        if (self.items.items.len > 0) {
            return self.items.orderedRemove(0);
        }
        
        return null;
    }
    
    fn shutdown(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.is_shutdown = true;
        self.condition.broadcast();
    }
};

/// Collects and orders results from parallel workers
const ResultCollector = struct {
    const Self = @This();
    
    results: std.ArrayList(ChunkResult),
    mutex: std.Thread.Mutex,
    
    fn init(allocator: Allocator) !Self {
        return Self{
            .results = std.ArrayList(ChunkResult).init(allocator),
            .mutex = .{},
        };
    }
    
    fn deinit(self: *Self) void {
        for (self.results.items) |*result| {
            result.tokens.deinit();
        }
        self.results.deinit();
    }
    
    fn addResult(self: *Self, result: ChunkResult) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.results.append(result) catch return;
    }
    
    fn getSortedResults(self: *Self) []ChunkResult {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Sort results by start position
        std.sort.insertion(ChunkResult, self.results.items, {}, struct {
            fn lessThan(_: void, a: ChunkResult, b: ChunkResult) bool {
                return a.start_pos < b.start_pos;
            }
        }.lessThan);
        
        return self.results.items;
    }
};

/// Main parallel JSON parser
pub const ParallelParser = struct {
    const Self = @This();
    
    allocator: Allocator,
    config: ParallelConfig,
    thread_pool: ThreadPool,
    
    pub fn init(allocator: Allocator, config: ParallelConfig) !Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .thread_pool = try ThreadPool.init(allocator, config),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.thread_pool.deinit(self.allocator);
    }
    
    /// Parse JSON data in parallel
    pub fn parse(self: *Self, data: []const u8) !std.ArrayList(Token) {
        // Check if data is large enough for parallel processing
        if (data.len < self.config.min_chunk_size) {
            // Fall back to single-threaded parsing
            return self.parseSingleThreaded(data);
        }
        
        // Partition data into chunks
        const chunks = try self.partitionData(data);
        defer self.allocator.free(chunks);
        
        // Start thread pool
        try self.thread_pool.start(self.allocator);
        defer self.thread_pool.stop();
        
        // Enqueue work items
        for (chunks, 0..) |chunk, i| {
            try self.thread_pool.work_queue.enqueue(WorkItem{
                .chunk = chunk,
                .data = data,
                .id = i,
            });
        }
        
        // Wait for all work to complete
        while (self.thread_pool.work_queue.items.items.len > 0 or 
               self.thread_pool.active_workers.load(.acquire) > 0) {
            std.time.sleep(1000000); // 1ms
        }
        
        // Merge results
        return try self.mergeResults();
    }
    
    /// Partition JSON data into chunks for parallel processing
    fn partitionData(self: *Self, data: []const u8) ![]JsonChunk {
        var chunks = std.ArrayList(JsonChunk).init(self.allocator);
        defer chunks.deinit();
        
        const chunk_size = self.config.target_chunk_size;
        var pos: usize = 0;
        const depth: i32 = 0;
        
        while (pos < data.len) {
            const start_pos = pos;
            const start_depth = depth;
            var boundary_type = BoundaryType.none;
            
            // Find a good chunk boundary
            const target_end = @min(pos + chunk_size, data.len);
            var end_pos = target_end;
            
            // Scan backwards to find a good split point
            if (end_pos < data.len) {
                var scan_pos = end_pos;
                const scan_limit = if (scan_pos > 1024) scan_pos - 1024 else 0;
                
                while (scan_pos > scan_limit) {
                    const c = data[scan_pos];
                    switch (c) {
                        '}', ']' => {
                            // Good split point after closing brace/bracket
                            end_pos = scan_pos + 1;
                            boundary_type = if (c == '}') .object else .array;
                            break;
                        },
                        ',' => {
                            // Good split point after comma
                            end_pos = scan_pos + 1;
                            break;
                        },
                        else => {},
                    }
                    scan_pos -= 1;
                }
            }
            
            try chunks.append(JsonChunk{
                .start = start_pos,
                .end = end_pos,
                .start_depth = start_depth,
                .boundary_type = boundary_type,
                .is_complete = (start_depth == 0 and boundary_type != .none),
            });
            
            pos = end_pos;
        }
        
        return self.allocator.dupe(JsonChunk, chunks.items);
    }
    
    /// Fall back to single-threaded parsing for small inputs
    fn parseSingleThreaded(self: *Self, data: []const u8) !std.ArrayList(Token) {
        var parser = try StreamingParser.init(self.allocator, self.config.parser_config);
        defer parser.deinit();
        
        var tokens = std.ArrayList(Token).init(self.allocator);
        
        var token_stream = try parser.parseStreaming(data);
        defer token_stream.deinit();
        
        // Copy tokens from stream
        while (token_stream.hasMore()) {
            if (token_stream.getCurrentToken()) |token| {
                try tokens.append(token);
            }
            token_stream.advance();
        }
        
        return tokens;
    }
    
    /// Merge results from parallel workers into a single token stream
    fn mergeResults(self: *Self) !std.ArrayList(Token) {
        const results = self.thread_pool.results.getSortedResults();
        
        var merged_tokens = std.ArrayList(Token).init(self.allocator);
        
        for (results) |result| {
            if (result.err) |_| {
                // Skip chunks with errors for now
                continue;
            }
            
            // Adjust token positions and add to merged stream
            for (result.tokens.items) |token| {
                var adjusted_token = token;
                adjusted_token.start += result.start_pos;
                adjusted_token.end += result.start_pos;
                
                try merged_tokens.append(adjusted_token);
            }
        }
        
        return merged_tokens;
    }
    
    /// Get performance statistics
    pub fn getStats(self: *Self) ParallelStats {
        const results = self.thread_pool.results.results.items;
        
        var total_time: u64 = 0;
        var max_time: u64 = 0;
        var min_time: u64 = std.math.maxInt(u64);
        var total_tokens: usize = 0;
        
        for (results) |result| {
            total_time += result.processing_time;
            max_time = @max(max_time, result.processing_time);
            min_time = @min(min_time, result.processing_time);
            total_tokens += result.tokens.items.len;
        }
        
        const avg_time = if (results.len > 0) total_time / results.len else 0;
        
        return ParallelStats{
            .num_chunks = results.len,
            .total_processing_time = total_time,
            .avg_chunk_time = avg_time,
            .max_chunk_time = max_time,
            .min_chunk_time = if (min_time == std.math.maxInt(u64)) 0 else min_time,
            .total_tokens = total_tokens,
        };
    }
};

/// Performance statistics for parallel parsing
pub const ParallelStats = struct {
    /// Number of chunks processed
    num_chunks: usize,
    
    /// Total processing time across all threads (nanoseconds)
    total_processing_time: u64,
    
    /// Average time per chunk (nanoseconds)
    avg_chunk_time: u64,
    
    /// Maximum chunk processing time
    max_chunk_time: u64,
    
    /// Minimum chunk processing time
    min_chunk_time: u64,
    
    /// Total number of tokens parsed
    total_tokens: usize,
    
    pub fn print(self: ParallelStats) void {
        std.debug.print("\n=== Parallel Parser Statistics ===\n", .{});
        std.debug.print("Chunks processed: {}\n", .{self.num_chunks});
        std.debug.print("Total tokens: {}\n", .{self.total_tokens});
        std.debug.print("Avg chunk time: {} μs\n", .{self.avg_chunk_time / 1000});
        std.debug.print("Max chunk time: {} μs\n", .{self.max_chunk_time / 1000});
        std.debug.print("Min chunk time: {} μs\n", .{self.min_chunk_time / 1000});
        std.debug.print("================================\n", .{});
    }
};