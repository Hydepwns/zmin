const std = @import("std");
const config = @import("config.zig");
const thread_pool = @import("thread_pool.zig");
const work_queue = @import("work_queue.zig");
const result_queue = @import("result_queue.zig");
const chunk_processor = @import("chunk_processor.zig");
const MinifyingParser = @import("../minifier/mod.zig").MinifyingParser;

pub const ParallelMinifier = struct {
    // Configuration
    config: config.Config,
    thread_count: usize,

    // Thread management
    thread_pool: ?thread_pool.ThreadPool,

    // Work distribution
    work_queue: work_queue.WorkQueue,

    // Result collection
    result_queue: result_queue.ResultQueue,

    // Chunk processing
    processor: chunk_processor.ChunkProcessor,

    // Output management
    output_writer: std.io.AnyWriter,
    output_buffer: std.ArrayList(u8),
    output_mutex: std.Thread.Mutex,

    // Input buffering
    input_buffer: std.ArrayList(u8),
    input_mutex: std.Thread.Mutex,

    // State tracking
    is_processing: bool,
    error_state: ?config.ParallelError,
    allocator: std.mem.Allocator,
    
    // Work tracking with atomic counters and synchronization
    work_submitted: std.atomic.Value(usize),
    work_completed: std.atomic.Value(usize),
    completion_mutex: std.Thread.Mutex,
    completion_cond: std.Thread.Condition,
    
    // Streaming support
    pending_output_chunks: std.ArrayList(config.StreamChunk),
    next_output_chunk_id: usize,
    streaming_mutex: std.Thread.Mutex,
    
    // Buffer reuse for performance
    reusable_buffers: std.ArrayList(std.ArrayList(u8)),
    buffer_mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn create(allocator: std.mem.Allocator, writer: std.io.AnyWriter, config_options: config.Config) !*Self {
        var self = try allocator.create(Self);
        self.* = try init(allocator, writer, config_options);
        
        // Now we can safely initialize the thread pool with a stable pointer
        if (self.thread_count > 1) {
            self.thread_pool = try thread_pool.ThreadPool.init(allocator, self.thread_count, workerThread, self);
        }
        
        return self;
    }
    
    pub fn destroy(self: *Self) void {
        const allocator = self.allocator;
        self.deinit();
        allocator.destroy(self);
    }
    
    pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter, config_options: config.Config) !Self {
        // Validate configuration
        try config_options.validate();
        const final_thread_count = config_options.getOptimalThreadCount();

        const minifier = Self{
            .config = config_options,
            .thread_count = final_thread_count,
            .thread_pool = null,
            .work_queue = work_queue.WorkQueue.init(allocator),
            .result_queue = result_queue.ResultQueue.init(allocator),
            .processor = chunk_processor.ChunkProcessor.init(allocator),
            .output_writer = writer,
            .output_buffer = std.ArrayList(u8).init(allocator),
            .output_mutex = .{},
            .input_buffer = std.ArrayList(u8).init(allocator),
            .input_mutex = .{},
            .is_processing = false,
            .error_state = null,
            .allocator = allocator,
            .work_submitted = std.atomic.Value(usize).init(0),
            .work_completed = std.atomic.Value(usize).init(0),
            .completion_mutex = .{},
            .completion_cond = .{},
            .pending_output_chunks = std.ArrayList(config.StreamChunk).init(allocator),
            .next_output_chunk_id = 0,
            .streaming_mutex = .{},
            .reusable_buffers = std.ArrayList(std.ArrayList(u8)).init(allocator),
            .buffer_mutex = .{},
        };

        // We can't initialize the thread pool here because 'minifier' is a local variable
        // whose address will change when we return it. The thread pool must be initialized
        // after the minifier is in its final location.
        
        return minifier;
    }

    pub fn deinit(self: *Self) void {
        if (self.thread_pool) |*pool| {
            pool.deinit();
        }
        self.work_queue.deinit();
        self.result_queue.deinit();
        self.processor.deinit();
        self.output_buffer.deinit();
        self.input_buffer.deinit();
        
        // Clean up pending output chunks
        for (self.pending_output_chunks.items) |*chunk| {
            var mutable_chunk = chunk.*;
            mutable_chunk.deinit(self.allocator);
        }
        self.pending_output_chunks.deinit();
        
        // Clean up reusable buffers
        for (self.reusable_buffers.items) |*buffer| {
            buffer.deinit();
        }
        self.reusable_buffers.deinit();
    }

    pub fn process(self: *Self, input: []const u8) !void {
        if (self.error_state) |err| return err;

        self.input_mutex.lock();
        defer self.input_mutex.unlock();

        // Add input to buffer
        try self.input_buffer.appendSlice(input);

        // Try to process any complete JSON structures we can identify
        try self.processAvailableJson();
    }

    fn processAvailableJson(self: *Self) !void {
        // For streaming, we need to be more sophisticated about when to process
        // For now, use the simple approach: wait for complete JSON
        if (self.hasCompleteJson()) {
            // Use adaptive threading based on input size
            const should_use_multiple_threads = self.shouldUseMultipleThreads();
            if (!should_use_multiple_threads) {
                try self.processSingleThreaded(self.input_buffer.items);
                self.input_buffer.clearRetainingCapacity();
            } else {
                try self.processMultiThreadedStreaming();
            }
        }
        // Note: In a production implementation, we would:
        // 1. Parse the JSON incrementally 
        // 2. Identify complete JSON values within the buffer
        // 3. Process those values while keeping incomplete parts buffered
    }

    fn hasCompleteJson(self: *Self) bool {
        // Simple check: if the input ends with '}' or ']', it might be complete
        // This is a basic heuristic - in a real implementation, you'd want more sophisticated parsing
        if (self.input_buffer.items.len == 0) return false;

        const last_char = self.input_buffer.items[self.input_buffer.items.len - 1];
        return last_char == '}' or last_char == ']';
    }

    pub fn flush(self: *Self) !void {
        if (self.error_state) |err| return err;

        // Process any remaining input in the buffer
        self.input_mutex.lock();
        defer self.input_mutex.unlock();

        if (self.input_buffer.items.len > 0) {
            // Force processing of any remaining data, even if incomplete
            const should_use_multiple_threads = self.shouldUseMultipleThreads();
            if (!should_use_multiple_threads) {
                try self.processSingleThreaded(self.input_buffer.items);
                self.input_buffer.clearRetainingCapacity();
            } else {
                try self.processMultiThreaded();
                // Wait for completion and merge results for final flush
                try self.waitForCompletion();
                try self.mergeResults();
            }
        }
    }

    fn shouldUseMultipleThreads(self: *Self) bool {
        // Only use multiple threads if:
        // 1. We have more than 1 thread configured
        // 2. Input is large enough to benefit from parallelism (> 1MB)
        // 3. Thread pool is available
        const min_size_for_parallel = 1024 * 1024; // 1MB
        return self.thread_count > 1 and 
               self.input_buffer.items.len > min_size_for_parallel and 
               self.thread_pool != null;
    }

    fn processSingleThreaded(self: *Self, input: []const u8) !void {
        var parser = try MinifyingParser.init(self.allocator, self.output_writer);
        defer parser.deinit(self.allocator);

        try parser.feed(input);
        try parser.flush();
    }

    fn processMultiThreaded(self: *Self) !void {
        // Ensure thread pool is running
        if (self.thread_pool) |*pool| {
            if (!pool.isRunning()) {
                return error.ThreadPoolNotRunning;
            }
        }
        
        // Reset counters for new batch of work
        self.resetCounters();
        
        // Split input into JSON-aware chunks
        const chunks = try self.processor.splitIntoChunks(self.input_buffer.items, self.config.chunk_size);
        // Note: We cannot free chunks here because worker threads may still be processing them
        // They will be freed when the work items are deinitialized


        // Add chunks to work queue and track submission count
        // Use errdefer to clean up on failure
        errdefer {
            // Clean up any chunks that weren't successfully queued
            for (chunks) |*chunk| {
                var mutable_chunk = chunk.*;
                mutable_chunk.deinit(self.allocator);
            }
            self.allocator.free(chunks);
        }
        
        for (chunks) |chunk| {
            try self.work_queue.push(chunk);
            _ = self.work_submitted.fetchAdd(1, .monotonic);
        }

        // Clear input buffer since we've processed it
        self.input_buffer.clearRetainingCapacity();
        
        // Free chunks array after work items are queued (chunks themselves are owned by work items)
        self.allocator.free(chunks);
    }

    fn processMultiThreadedStreaming(self: *Self) !void {
        // For streaming, we need to maintain order and handle partial completion
        // For now, delegate to the standard multi-threaded processing
        // In a full implementation, this would handle incremental output
        try self.processMultiThreaded();
        
        // Wait for completion and write results immediately for streaming
        try self.waitForCompletion();
        try self.flushStreamingOutput();
    }

    fn flushStreamingOutput(self: *Self) !void {
        // Get all results and write them in order
        const results = self.result_queue.popAll();
        defer self.allocator.free(results);

        if (results.len == 0) {
            return; // No results to flush
        }

        // Sort results by chunk ID to maintain order
        std.mem.sort(config.ChunkResult, results, {}, struct {
            fn lessThan(_: void, a: config.ChunkResult, b: config.ChunkResult) bool {
                return a.chunk_id < b.chunk_id;
            }
        }.lessThan);

        // Write results directly to output writer for streaming
        for (results) |result| {
            try self.output_writer.writeAll(result.output);
            var result_copy = result;
            result_copy.deinit(self.allocator);
        }
    }

    fn waitForCompletion(self: *Self) !void {
        // If no thread pool is used, there's nothing to wait for
        if (self.thread_pool == null) {
            return;
        }

        self.completion_mutex.lock();
        defer self.completion_mutex.unlock();

        // Wait for all work items to be processed using condition variable
        const timeout_ns = 30 * std.time.ns_per_s; // 30 second timeout
        const deadline = std.time.nanoTimestamp() + timeout_ns;
        
        while (true) {
            const submitted = self.work_submitted.load(.acquire);
            const completed = self.work_completed.load(.acquire);
            
            // Check if all submitted work has been completed
            if (submitted > 0 and completed >= submitted) {
                break;
            }
            
            // Check for timeout
            const now = std.time.nanoTimestamp();
            if (now >= deadline) {
                return error.TimeoutWaitingForCompletion;
            }
            
            // Wait with timeout for completion signal
            const remaining_ns = @as(u64, @intCast(deadline - now));
            self.completion_cond.timedWait(&self.completion_mutex, remaining_ns) catch {
                // Timeout occurred, check one more time before failing
                const final_submitted = self.work_submitted.load(.acquire);
                const final_completed = self.work_completed.load(.acquire);
                if (final_submitted > 0 and final_completed >= final_submitted) {
                    break;
                }
                return error.TimeoutWaitingForCompletion;
            };
        }

        // Collect and merge results
        try self.mergeResults();
    }

    fn mergeResults(self: *Self) !void {
        // Get all results and sort by chunk ID
        const results = self.result_queue.popAll();
        defer self.allocator.free(results);

        if (results.len == 0) {
            return; // No results to merge
        }

        // Sort results by chunk ID to maintain order
        std.mem.sort(config.ChunkResult, results, {}, struct {
            fn lessThan(_: void, a: config.ChunkResult, b: config.ChunkResult) bool {
                return a.chunk_id < b.chunk_id;
            }
        }.lessThan);

        // Write results directly to output writer
        for (results) |result| {
            try self.output_writer.writeAll(result.output);
            var result_copy = result;
            result_copy.deinit(self.allocator);
        }
    }

    fn workerThread(context: *Self, thread_id: usize) void {
        _ = thread_id; // Used for debugging when needed
        // Create a thread-local allocator and processor
        var thread_arena = std.heap.ArenaAllocator.init(context.allocator);
        defer thread_arena.deinit();
        
        var thread_processor = chunk_processor.ChunkProcessor.init(thread_arena.allocator());
        
        // Wait for the thread pool to start (only if thread pool exists)
        if (context.thread_pool) |*pool| {
            while (true) {
                if (pool.isStarted()) {
                    break;
                }
                if (pool.shouldStop()) {
                    return; // Exit immediately if we should stop
                }
                std.time.sleep(100 * std.time.ns_per_us); // 100 microseconds
            }
        }

        // Main work loop
        var work_count: usize = 0;
        while (true) {
            // Check if we should stop
            if (context.thread_pool) |*pool| {
                if (pool.shouldStop()) {
                    break;
                }
            }

            // Get work item (non-blocking)
            const work_item = context.work_queue.popNonBlocking();
            if (work_item) |item| {
                work_count += 1;

                // Process the chunk using thread-local processor but allocate result with main allocator
                const result = thread_processor.processChunkWithAllocator(item, context.allocator) catch {
                    // Map error to ParallelError type
                    context.error_state = config.ParallelError.ChunkProcessingFailed;
                    
                    // Clean up work item memory if it owns memory
                    var mutable_item = item;
                    mutable_item.deinit(context.allocator);
                    
                    _ = context.work_completed.fetchAdd(1, .monotonic);
                    
                    // Signal completion even on error
                    context.completion_mutex.lock();
                    context.completion_cond.signal();
                    context.completion_mutex.unlock();
                    continue;
                };

                // Clean up work item memory if it owns memory
                var mutable_item = item;
                mutable_item.deinit(context.allocator);

                // Add result to result queue
                context.result_queue.push(result) catch {
                    context.error_state = config.ParallelError.ResultQueueFull;
                    var mutable_result = result;
                    mutable_result.deinit(context.allocator);
                    _ = context.work_completed.fetchAdd(1, .monotonic);
                    
                    // Signal completion even on error
                    context.completion_mutex.lock();
                    context.completion_cond.signal();
                    context.completion_mutex.unlock();
                    continue;
                };
                
                // Increment completed counter and signal completion
                _ = context.work_completed.fetchAdd(1, .monotonic);
                
                // Signal potential waiters that work has been completed
                context.completion_mutex.lock();
                context.completion_cond.signal();
                context.completion_mutex.unlock();
            } else {
                // No work available, sleep briefly to avoid busy waiting
                std.time.sleep(100 * std.time.ns_per_us); // 100 microseconds
            }
        }
    }

    pub fn getOutput(self: *Self) []const u8 {
        self.output_mutex.lock();
        defer self.output_mutex.unlock();

        return self.output_buffer.items;
    }

    pub fn copyOutputTo(self: *Self, target: *std.ArrayList(u8)) !void {
        self.output_mutex.lock();
        defer self.output_mutex.unlock();

        try target.appendSlice(self.output_buffer.items);
    }

    pub fn clearOutput(self: *Self) void {
        self.output_mutex.lock();
        defer self.output_mutex.unlock();

        self.output_buffer.clearRetainingCapacity();
    }

    pub fn getConfig(self: *Self) config.Config {
        return self.config;
    }

    pub fn getThreadCount(self: *Self) usize {
        return self.thread_count;
    }

    pub fn getErrorState(self: *Self) ?config.ParallelError {
        return self.error_state;
    }

    pub fn clearError(self: *Self) void {
        self.error_state = null;
    }
    
    fn resetCounters(self: *Self) void {
        self.work_submitted.store(0, .release);
        self.work_completed.store(0, .release);
    }
    
};
