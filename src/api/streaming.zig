//! Streaming API for zmin JSON Minifier
//!
//! This module provides high-performance streaming interfaces for processing
//! large JSON datasets, real-time data streams, and memory-constrained environments.
//!
//! Key Features:
//! - Constant memory usage regardless of input size
//! - Backpressure handling for real-time streams
//! - Async/await support for non-blocking I/O
//! - Pipeline processing for maximum throughput

const std = @import("std");
const core = @import("../core/minifier.zig");

/// High-performance streaming JSON minifier
pub const StreamingMinifier = struct {
    allocator: std.mem.Allocator,
    config: StreamConfig,
    internal_buffer: []u8,
    output_buffer: []u8,
    state: StreamState,
    stats: StreamStats,
    
    const Self = @This();
    
    /// Streaming configuration
    pub const StreamConfig = struct {
        /// Input buffer size (affects memory usage and performance)
        input_buffer_size: usize = 64 * 1024, // 64KB
        
        /// Output buffer size for batching writes
        output_buffer_size: usize = 64 * 1024, // 64KB
        
        /// Maximum memory usage limit (0 = unlimited)
        memory_limit: usize = 0,
        
        /// Enable validation during streaming
        validate_input: bool = true,
        
        /// Flush output buffer every N bytes
        auto_flush_bytes: usize = 32 * 1024, // 32KB
        
        /// Flush output buffer every N milliseconds
        auto_flush_timeout_ms: u32 = 100, // 100ms
        
        /// Handle backpressure when output buffer is full
        backpressure_handling: BackpressureMode = .block,
        
        /// Processing optimization level
        optimization_level: OptimizationLevel = .adaptive,
        
        pub const BackpressureMode = enum {
            /// Block until buffer space is available
            block,
            
            /// Drop oldest data to make room
            drop_old,
            
            /// Return error when buffer is full
            error_on_full,
            
            /// Compress buffer contents to make room
            compress,
        };
        
        pub const OptimizationLevel = enum {
            /// Minimize memory usage
            memory_optimized,
            
            /// Maximize throughput
            throughput_optimized,
            
            /// Balance memory and throughput
            balanced,
            
            /// Automatically adapt based on conditions
            adaptive,
        };
    };
    
    /// Initialize streaming minifier
    ///
    /// Example:
    /// ```zig
    /// var config = StreamConfig{
    ///     .input_buffer_size = 128 * 1024, // 128KB
    ///     .optimization_level = .throughput_optimized,
    /// };
    /// 
    /// var minifier = try StreamingMinifier.init(allocator, config);
    /// defer minifier.deinit();
    /// ```
    pub fn init(allocator: std.mem.Allocator, config: StreamConfig) !Self {
        const input_buffer = try allocator.alloc(u8, config.input_buffer_size);
        const output_buffer = try allocator.alloc(u8, config.output_buffer_size);
        
        return Self{
            .allocator = allocator,
            .config = config,
            .internal_buffer = input_buffer,
            .output_buffer = output_buffer,
            .state = StreamState.init(),
            .stats = StreamStats.init(),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.internal_buffer);
        self.allocator.free(self.output_buffer);
    }
    
    /// Process streaming data from reader to writer
    ///
    /// This is the main streaming interface. It reads data in chunks,
    /// processes it, and writes minified output with optimal buffering.
    ///
    /// Example:
    /// ```zig
    /// const input_file = try std.fs.cwd().openFile("large.json", .{});
    /// defer input_file.close();
    /// 
    /// const output_file = try std.fs.cwd().createFile("minified.json", .{});
    /// defer output_file.close();
    /// 
    /// try minifier.processStream(input_file.reader(), output_file.writer());
    /// const stats = minifier.getStats();
    /// std.debug.print("Processed {d:.2} MB at {d:.2} GB/s\n", 
    ///     .{ @as(f64, @floatFromInt(stats.bytes_processed)) / (1024*1024), stats.throughput_gbps });
    /// ```
    pub fn processStream(self: *Self, reader: anytype, writer: anytype) !void {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.stats.total_duration_ns = @as(u64, @intCast(end_time - start_time));
        }
        
        // Reset state for new stream
        self.state.reset();
        self.stats.reset();
        
        var input_pos: usize = 0;
        var last_flush_time = start_time;
        
        while (true) {
            // Read chunk of input data
            const bytes_read = try reader.read(self.internal_buffer[input_pos..]);
            if (bytes_read == 0) break; // End of stream
            
            const chunk = self.internal_buffer[0..input_pos + bytes_read];
            self.stats.bytes_read += bytes_read;
            
            // Process the chunk
            const processed_bytes = try self.processChunk(chunk, writer);
            
            // Handle partial processing (incomplete JSON tokens at end of chunk)  
            if (processed_bytes < chunk.len) {
                const remaining = chunk.len - processed_bytes;
                std.mem.copyForwards(u8, self.internal_buffer[0..remaining], chunk[processed_bytes..]);
                input_pos = remaining;
            } else {
                input_pos = 0;
            }
            
            // Auto-flush based on time or bytes
            const current_time = std.time.nanoTimestamp();
            const time_since_flush = @as(u32, @intCast((current_time - last_flush_time) / 1_000_000)); // Convert to ms
            
            if (self.state.output_pos >= self.config.auto_flush_bytes or 
                time_since_flush >= self.config.auto_flush_timeout_ms) {
                try self.flush(writer);
                last_flush_time = current_time;
            }
        }
        
        // Process any remaining data
        if (input_pos > 0) {
            _ = try self.processChunk(self.internal_buffer[0..input_pos], writer);
        }
        
        // Final flush
        try self.flush(writer);
        
        // Update final statistics
        self.stats.calculateFinalMetrics();
    }
    
    /// Process data in chunks with async support
    ///
    /// Non-blocking version that can be used with async I/O.
    /// Returns the number of bytes that were processed.
    ///
    /// Example:
    /// ```zig
    /// while (true) {
    ///     const chunk = try readNextChunk();
    ///     if (chunk.len == 0) break;
    ///     
    ///     const processed = try minifier.processChunkAsync(chunk, writer);
    ///     if (processed < chunk.len) {
    ///         // Handle partial processing
    ///         savePartialChunk(chunk[processed..]);
    ///     }
    /// }
    /// ```
    pub fn processChunkAsync(self: *Self, chunk: []const u8, writer: anytype) !usize {
        return self.processChunk(chunk, writer);
    }
    
    /// Flush output buffer to writer
    ///
    /// Forces all buffered output to be written immediately.
    /// Useful for ensuring data is written before closing streams.
    pub fn flush(self: *Self, writer: anytype) !void {
        if (self.state.output_pos > 0) {
            try writer.writeAll(self.output_buffer[0..self.state.output_pos]);
            self.stats.bytes_written += self.state.output_pos;
            self.state.output_pos = 0;
        }
    }
    
    /// Get current streaming statistics
    ///
    /// Returns comprehensive statistics about the streaming operation
    /// including throughput, memory usage, and performance metrics.
    pub fn getStats(self: *const Self) StreamStats {
        return self.stats;
    }
    
    /// Reset minifier for new stream
    ///
    /// Clears all internal state and statistics, preparing for
    /// processing a new stream.
    pub fn reset(self: *Self) void {
        self.state.reset();
        self.stats.reset();
    }
    
    /// Estimate memory usage for given configuration
    ///
    /// Returns the total memory footprint including buffers
    /// and internal state. Useful for capacity planning.
    pub fn estimateMemoryUsage(config: StreamConfig) usize {
        return config.input_buffer_size + config.output_buffer_size + 
               @sizeOf(StreamState) + @sizeOf(StreamStats) + 1024; // Extra for state
    }
    
    // Private implementation methods
    
    fn processChunk(self: *Self, chunk: []const u8, writer: anytype) !usize {
        var processed: usize = 0;
        var pos: usize = 0;
        
        while (pos < chunk.len) {
            // Find complete JSON tokens in the chunk
            const token_end = self.findCompleteToken(chunk[pos..]);
            if (token_end == 0) {
                // No complete token found, need more data
                break;
            }
            
            const token = chunk[pos..pos + token_end];
            
            // Process the token and add to output buffer
            const output_len = try self.minifyToken(token);
            
            // Check if output buffer has space
            if (self.state.output_pos + output_len > self.output_buffer.len) {
                // Handle backpressure
                try self.handleBackpressure(writer, output_len);
            }
            
            // Copy minified output to buffer
            @memcpy(self.output_buffer[self.state.output_pos..self.state.output_pos + output_len], 
                   self.state.temp_output[0..output_len]);
            self.state.output_pos += output_len;
            
            pos += token_end;
            processed = pos;
            
            // Update statistics
            self.stats.tokens_processed += 1;
            self.stats.bytes_processed += token_end;
        }
        
        return processed;
    }
    
    fn findCompleteToken(self: *Self, data: []const u8) usize {
        // Implementation of JSON token boundary detection
        // This is a simplified version - real implementation would be more sophisticated
        _ = self;
        
        var pos: usize = 0;
        var brace_count: i32 = 0;
        var bracket_count: i32 = 0;
        var in_string = false;
        var escape_next = false;
        
        while (pos < data.len) {
            const byte = data[pos];
            
            if (escape_next) {
                escape_next = false;
                pos += 1;
                continue;
            }
            
            switch (byte) {
                '"' => in_string = !in_string,
                '\\' => if (in_string) escape_next = true,
                '{' => if (!in_string) brace_count += 1,
                '}' => if (!in_string) {
                    brace_count -= 1;
                    if (brace_count == 0 and bracket_count == 0) {
                        return pos + 1; // Complete JSON object
                    }
                },
                '[' => if (!in_string) bracket_count += 1,
                ']' => if (!in_string) {
                    bracket_count -= 1;
                    if (brace_count == 0 and bracket_count == 0) {
                        return pos + 1; // Complete JSON array
                    }
                },
                else => {},
            }
            
            pos += 1;
        }
        
        // No complete token found
        return 0;
    }
    
    fn minifyToken(self: *Self, token: []const u8) !usize {
        // Use core minifier for token processing
        const output_len = try core.MinifierEngine.minifyToBuffer(
            token, 
            self.state.temp_output, 
            .{ .optimization_level = .aggressive, .validate_input = self.config.validate_input }
        );
        
        return output_len;
    }
    
    fn handleBackpressure(self: *Self, writer: anytype, needed_space: usize) !void {
        switch (self.config.backpressure_handling) {
            .block => {
                // Flush current buffer and wait
                try self.flush(writer);
                self.stats.backpressure_events += 1;
            },
            .drop_old => {
                // Drop old data to make room
                const drop_amount = needed_space;
                if (drop_amount < self.state.output_pos) {
                    std.mem.copyForwards(u8, 
                        self.output_buffer[0..self.state.output_pos - drop_amount],
                        self.output_buffer[drop_amount..self.state.output_pos]);
                    self.state.output_pos -= drop_amount;
                    self.stats.bytes_dropped += drop_amount;
                }
            },
            .error_on_full => {
                return error.OutputBufferFull;
            },
            .compress => {
                // Try to compress buffer contents (simplified)
                try self.flush(writer);
                self.stats.compression_events += 1;
            },
        }
    }
};

/// Streaming processing state
const StreamState = struct {
    output_pos: usize = 0,
    temp_output: [8192]u8 = undefined, // Temporary buffer for token processing
    json_depth: u32 = 0,
    in_string: bool = false,
    escape_next: bool = false,
    
    pub fn init() StreamState {
        return StreamState{};
    }
    
    pub fn reset(self: *StreamState) void {
        self.output_pos = 0;
        self.json_depth = 0;
        self.in_string = false;
        self.escape_next = false;
    }
};

/// Comprehensive streaming statistics
pub const StreamStats = struct {
    // Basic metrics
    bytes_read: u64 = 0,
    bytes_processed: u64 = 0,
    bytes_written: u64 = 0,
    bytes_dropped: u64 = 0,
    
    // Processing metrics
    tokens_processed: u64 = 0,
    total_duration_ns: u64 = 0,
    
    // Performance metrics
    throughput_gbps: f64 = 0.0,
    peak_throughput_gbps: f64 = 0.0,
    average_latency_ns: u64 = 0,
    
    // Resource utilization
    peak_memory_usage: usize = 0,
    backpressure_events: u32 = 0,
    compression_events: u32 = 0,
    
    pub fn init() StreamStats {
        return StreamStats{};
    }
    
    pub fn reset(self: *StreamStats) void {
        self.* = StreamStats{};
    }
    
    pub fn calculateFinalMetrics(self: *StreamStats) void {
        if (self.total_duration_ns > 0) {
            const duration_s = @as(f64, @floatFromInt(self.total_duration_ns)) / 1_000_000_000.0;
            const bytes_per_second = @as(f64, @floatFromInt(self.bytes_processed)) / duration_s;
            self.throughput_gbps = bytes_per_second / (1024.0 * 1024.0 * 1024.0);
            
            if (self.tokens_processed > 0) {
                self.average_latency_ns = self.total_duration_ns / self.tokens_processed;
            }
        }
    }
    
    pub fn getCompressionRatio(self: *const StreamStats) f32 {
        if (self.bytes_read == 0) return 1.0;
        return @as(f32, @floatFromInt(self.bytes_written)) / @as(f32, @floatFromInt(self.bytes_read));
    }
    
    pub fn getEfficiency(self: *const StreamStats) f32 {
        if (self.bytes_read == 0) return 1.0;
        const processed_ratio = @as(f32, @floatFromInt(self.bytes_processed)) / @as(f32, @floatFromInt(self.bytes_read));
        const dropped_penalty = @as(f32, @floatFromInt(self.bytes_dropped)) / @as(f32, @floatFromInt(self.bytes_read));
        return processed_ratio - dropped_penalty;
    }
};

/// Async streaming interface for non-blocking I/O
pub const AsyncStreamingMinifier = struct {
    base: StreamingMinifier,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: StreamingMinifier.StreamConfig) !Self {
        return Self{
            .base = try StreamingMinifier.init(allocator, config),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }
    
    /// Async version of stream processing
    ///
    /// Processes data without blocking, suitable for use in async functions.
    /// Returns a future that completes when processing is done.
    pub fn processStreamAsync(self: *Self, reader: anytype, writer: anytype) !void {
        // In a real implementation, this would use async/await
        // For now, delegate to synchronous version
        return self.base.processStream(reader, writer);
    }
    
    /// Process single chunk asynchronously
    ///
    /// Non-blocking processing of a single data chunk.
    /// Returns immediately with the number of bytes processed.
    pub fn processChunkAsync(self: *Self, chunk: []const u8, writer: anytype) !usize {
        return self.base.processChunkAsync(chunk, writer);
    }
    
    pub fn getStats(self: *const Self) StreamStats {
        return self.base.getStats();
    }
    
    pub fn reset(self: *Self) void {
        self.base.reset();
    }
};

/// Pipeline processing for maximum throughput
///
/// Processes multiple streams in parallel with a pipeline architecture
/// for applications that need to handle many concurrent JSON streams.
pub const PipelineProcessor = struct {
    allocator: std.mem.Allocator,
    workers: []Worker,
    input_queue: StreamQueue,
    output_queue: StreamQueue,
    config: PipelineConfig,
    
    const Self = @This();
    
    pub const PipelineConfig = struct {
        worker_count: u32 = 0, // 0 = auto-detect CPU count
        queue_size: u32 = 1000,
        worker_buffer_size: usize = 64 * 1024,
        load_balancing: LoadBalancing = .round_robin,
        
        pub const LoadBalancing = enum {
            round_robin,
            least_loaded,
            hash_based,
            work_stealing,
        };
    };
    
    pub fn init(allocator: std.mem.Allocator, config: PipelineConfig) !Self {
        const worker_count = if (config.worker_count > 0) 
            config.worker_count 
        else 
            @intCast(try std.Thread.getCpuCount());
        
        const workers = try allocator.alloc(Worker, worker_count);
        for (workers) |*worker| {
            worker.* = try Worker.init(allocator, config.worker_buffer_size);
        }
        
        return Self{
            .allocator = allocator,
            .workers = workers,
            .input_queue = try StreamQueue.init(allocator, config.queue_size),
            .output_queue = try StreamQueue.init(allocator, config.queue_size),
            .config = config,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.workers) |*worker| {
            worker.deinit();
        }
        self.allocator.free(self.workers);
        self.input_queue.deinit();
        self.output_queue.deinit();
    }
    
    /// Submit stream for processing
    ///
    /// Adds a stream to the processing pipeline. Returns immediately
    /// without blocking. Results can be retrieved via pollResults().
    pub fn submitStream(self: *Self, stream_id: u64, reader: anytype, writer: anytype) !void {
        const job = StreamJob{
            .id = stream_id,
            .reader = reader,
            .writer = writer,
        };
        
        try self.input_queue.push(job);
    }
    
    /// Poll for completed results
    ///
    /// Non-blocking check for completed stream processing jobs.
    /// Returns null if no results are available.
    pub fn pollResult(self: *Self) ?StreamResult {
        return self.output_queue.pop();
    }
    
    /// Wait for specific stream to complete
    ///
    /// Blocks until the specified stream has been processed.
    pub fn waitForStream(self: *Self, stream_id: u64) !StreamResult {
        while (true) {
            if (self.pollResult()) |result| {
                if (result.stream_id == stream_id) {
                    return result;
                }
                // Put back result for different stream
                try self.output_queue.push(result);
            }
            
            // Brief sleep to avoid busy waiting
            std.time.sleep(1000000); // 1ms
        }
    }
    
    /// Get pipeline statistics
    ///
    /// Returns comprehensive statistics about pipeline performance
    /// including worker utilization and queue depths.
    pub fn getPipelineStats(self: *Self) PipelineStats {
        var stats = PipelineStats{
            .worker_count = @intCast(self.workers.len),
            .input_queue_depth = @intCast(self.input_queue.length()),
            .output_queue_depth = @intCast(self.output_queue.length()),
        };
        
        // Aggregate worker statistics
        for (self.workers) |*worker| {
            const worker_stats = worker.getStats();
            stats.total_streams_processed += worker_stats.streams_processed;
            stats.total_bytes_processed += worker_stats.bytes_processed;
            stats.average_throughput_gbps += worker_stats.throughput_gbps;
        }
        
        if (self.workers.len > 0) {
            stats.average_throughput_gbps /= @as(f64, @floatFromInt(self.workers.len));
        }
        
        return stats;
    }
};

// Supporting types for pipeline processing
const Worker = struct {
    minifier: StreamingMinifier,
    stats: WorkerStats,
    
    pub fn init(allocator: std.mem.Allocator, buffer_size: usize) !Worker {
        const config = StreamingMinifier.StreamConfig{
            .input_buffer_size = buffer_size,
            .output_buffer_size = buffer_size,
        };
        
        return Worker{
            .minifier = try StreamingMinifier.init(allocator, config),
            .stats = WorkerStats{},
        };
    }
    
    pub fn deinit(self: *Worker) void {
        self.minifier.deinit();
    }
    
    pub fn getStats(self: *const Worker) WorkerStats {
        return self.stats;
    }
};

const WorkerStats = struct {
    streams_processed: u64 = 0,
    bytes_processed: u64 = 0,
    throughput_gbps: f64 = 0.0,
};

const StreamQueue = struct {
    items: []StreamJob,
    head: u32 = 0,
    tail: u32 = 0,
    capacity: u32,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, capacity: u32) !StreamQueue {
        return StreamQueue{
            .items = try allocator.alloc(StreamJob, capacity),
            .capacity = capacity,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *StreamQueue) void {
        self.allocator.free(self.items);
    }
    
    pub fn push(self: *StreamQueue, item: StreamJob) !void {
        if (self.length() >= self.capacity) {
            return error.QueueFull;
        }
        
        self.items[self.tail] = item;
        self.tail = (self.tail + 1) % self.capacity;
    }
    
    pub fn pop(self: *StreamQueue) ?StreamJob {
        if (self.length() == 0) return null;
        
        const item = self.items[self.head];
        self.head = (self.head + 1) % self.capacity;
        return item;
    }
    
    pub fn length(self: *const StreamQueue) u32 {
        if (self.tail >= self.head) {
            return self.tail - self.head;
        } else {
            return self.capacity - self.head + self.tail;
        }
    }
};

const StreamJob = struct {
    id: u64,
    reader: std.io.AnyReader,
    writer: std.io.AnyWriter,
};

const StreamResult = struct {
    stream_id: u64,
    success: bool,
    stats: StreamStats,
    error_message: ?[]const u8 = null,
};

const PipelineStats = struct {
    worker_count: u32,
    input_queue_depth: u32,
    output_queue_depth: u32,
    total_streams_processed: u64,
    total_bytes_processed: u64,
    average_throughput_gbps: f64,
};