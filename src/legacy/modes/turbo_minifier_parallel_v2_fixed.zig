// TURBO Mode Parallel V2 - Fixed version with proper work item handling
// Fixes the bug where workers were modifying copies instead of originals

const std = @import("std");
const builtin = @import("builtin");
const optimized_work_stealing = @import("optimized_work_stealing");
const memory_optimizer = @import("memory_optimizer");

pub const TurboMinifierParallelV2 = struct {
    allocator: std.mem.Allocator,
    work_stealer: optimized_work_stealing.OptimizedWorkStealer,
    worker_threads: []std.Thread,
    memory_opt: memory_optimizer.MemoryOptimizer,
    config: ParallelConfig,
    
    // Thread synchronization
    workers_ready: std.atomic.Value(u32),
    start_signal: std.atomic.Value(bool),
    shutdown: std.atomic.Value(bool),
    
    // Performance tracking
    total_bytes_processed: std.atomic.Value(u64),
    total_processing_time: std.atomic.Value(u64),
    total_chunks_processed: std.atomic.Value(u64),
    
    // Work items storage - FIXED: Store pointers to allow modification
    work_items_storage: []optimized_work_stealing.OptimizedWorkStealer.WorkItem,
    work_items_mutex: std.Thread.Mutex,
    
    pub const ParallelConfig = struct {
        thread_count: usize = 0, // 0 = auto-detect
        chunk_size: usize = 256 * 1024, // 256KB default
        enable_work_stealing: bool = true,
        enable_numa: bool = true,
        prefetch_distance: usize = 512,
        adaptive_chunking: bool = true,
    };
    
    pub fn init(allocator: std.mem.Allocator, config: ParallelConfig) !TurboMinifierParallelV2 {
        const thread_count = if (config.thread_count == 0)
            try std.Thread.getCpuCount()
        else
            config.thread_count;
            
        const worker_threads = try allocator.alloc(std.Thread, thread_count);
        errdefer allocator.free(worker_threads);
        
        var self = TurboMinifierParallelV2{
            .allocator = allocator,
            .work_stealer = try optimized_work_stealing.OptimizedWorkStealer.init(allocator, thread_count),
            .worker_threads = worker_threads,
            .memory_opt = try memory_optimizer.MemoryOptimizer.init(allocator),
            .config = config,
            .workers_ready = std.atomic.Value(u32).init(0),
            .start_signal = std.atomic.Value(bool).init(false),
            .shutdown = std.atomic.Value(bool).init(false),
            .total_bytes_processed = std.atomic.Value(u64).init(0),
            .total_processing_time = std.atomic.Value(u64).init(0),
            .total_chunks_processed = std.atomic.Value(u64).init(0),
            .work_items_storage = &[_]optimized_work_stealing.OptimizedWorkStealer.WorkItem{},
            .work_items_mutex = .{},
        };
        
        // Start worker threads
        for (worker_threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerThread, .{ &self, i });
        }
        
        // Wait for workers to be ready
        while (self.workers_ready.load(.acquire) < thread_count) {
            std.Thread.yield() catch {};
        }
        
        return self;
    }
    
    pub fn deinit(self: *TurboMinifierParallelV2) void {
        // Signal shutdown
        self.shutdown.store(true, .release);
        self.start_signal.store(true, .release);
        
        // Wait for threads
        for (self.worker_threads) |thread| {
            thread.join();
        }
        
        // Cleanup
        self.work_stealer.deinit();
        self.memory_opt.deinit();
        self.allocator.free(self.worker_threads);
        if (self.work_items_storage.len > 0) {
            self.allocator.free(self.work_items_storage);
        }
    }
    
    pub fn minify(self: *TurboMinifierParallelV2, input: []const u8, output: []u8) !usize {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            _ = self.total_bytes_processed.fetchAdd(input.len, .monotonic);
            _ = self.total_processing_time.fetchAdd(@as(u64, @intCast(end_time - start_time)), .monotonic);
        }
        
        // For small inputs, use optimized single-threaded path
        if (input.len < self.config.chunk_size) {
            return self.minifySingleThreadedOptimized(input, output);
        }
        
        // Calculate optimal chunking
        const chunk_info = self.calculateOptimalChunking(input);
        
        // Allocate work items storage
        {
            self.work_items_mutex.lock();
            defer self.work_items_mutex.unlock();
            
            if (self.work_items_storage.len > 0) {
                self.allocator.free(self.work_items_storage);
            }
            self.work_items_storage = try self.allocator.alloc(
                optimized_work_stealing.OptimizedWorkStealer.WorkItem, 
                chunk_info.chunk_count
            );
        }
        
        var temp_buffers = try self.allocator.alloc([]u8, chunk_info.chunk_count);
        defer {
            for (temp_buffers) |buffer| {
                self.allocator.free(buffer);
            }
            self.allocator.free(temp_buffers);
        }
        
        // Initialize work items
        var chunk_start: usize = 0;
        for (0..chunk_info.chunk_count) |i| {
            const chunk_end = if (i < chunk_info.chunk_count - 1)
                chunk_info.chunk_boundaries[i + 1]
            else
                input.len;
                
            const chunk = input[chunk_start..chunk_end];
            temp_buffers[i] = try self.allocator.alloc(u8, chunk.len);
            
            const priority: u8 = if (chunk.len > 1024 * 1024) 255 else @intCast(chunk.len / 4096);
            const numa_node: u8 = if (self.config.enable_numa) @intCast(i % getNumaNodeCount()) else 0;
            
            self.work_items_storage[i] = optimized_work_stealing.OptimizedWorkStealer.WorkItem.init(
                @intCast(i),
                chunk,
                temp_buffers[i],
                priority,
                numa_node
            );
            
            // Submit pointer to work item instead of copy
            const preferred_thread = if (self.config.enable_numa)
                numa_node * (self.worker_threads.len / getNumaNodeCount())
            else
                i % self.worker_threads.len;
                
            try self.work_stealer.submitWorkPtr(&self.work_items_storage[i], preferred_thread);
            
            chunk_start = chunk_end;
        }
        
        // Signal workers to start
        self.start_signal.store(true, .release);
        
        // Wait for completion
        var completed: usize = 0;
        while (completed < chunk_info.chunk_count) {
            completed = 0;
            for (self.work_items_storage) |*item| {
                if (item.completed.load(.acquire)) {
                    completed += 1;
                }
            }
            if (completed < chunk_info.chunk_count) {
                std.Thread.yield() catch {};
            }
        }
        
        // Reset start signal
        self.start_signal.store(false, .release);
        
        // Update stats
        _ = self.total_chunks_processed.fetchAdd(chunk_info.chunk_count, .monotonic);
        
        // Merge results
        return self.mergeResults(self.work_items_storage, output);
    }
    
    fn workerThread(self: *TurboMinifierParallelV2, thread_id: usize) void {
        // Signal ready
        _ = self.workers_ready.fetchAdd(1, .release);
        
        while (!self.shutdown.load(.acquire)) {
            // Wait for start signal
            while (!self.start_signal.load(.acquire) and !self.shutdown.load(.acquire)) {
                std.Thread.yield() catch {};
            }
            
            if (self.shutdown.load(.acquire)) break;
            
            // Process work - FIXED: Now working with pointers
            while (self.work_stealer.getWorkPtr(thread_id)) |work_item_ptr| {
                optimized_work_stealing.OptimizedWorkStealer.processWork(work_item_ptr);
            }
        }
    }
    
    fn minifySingleThreadedOptimized(self: *TurboMinifierParallelV2, input: []const u8, output: []u8) !usize {
        return try self.memory_opt.optimizeAccess(input, output);
    }
    
    const ChunkInfo = struct {
        chunk_count: usize,
        chunk_boundaries: []usize,
    };
    
    fn calculateOptimalChunking(self: *TurboMinifierParallelV2, input: []const u8) ChunkInfo {
        const thread_count = self.worker_threads.len;
        const min_chunk_size = self.config.chunk_size;
        
        // Adaptive chunking based on input size and thread count
        const target_chunks = thread_count * 4; // 4x oversubscription for load balancing
        const ideal_chunk_size = input.len / target_chunks;
        const chunk_size = @max(min_chunk_size, ideal_chunk_size);
        
        var boundaries = std.ArrayList(usize).init(self.allocator);
        boundaries.append(0) catch unreachable;
        
        if (!self.config.adaptive_chunking) {
            // Simple fixed-size chunking
            var pos = chunk_size;
            while (pos < input.len) {
                boundaries.append(pos) catch unreachable;
                pos += chunk_size;
            }
        } else {
            // JSON-aware chunking
            const target_chunk_size = chunk_size;
            
            var pos: usize = target_chunk_size;
            var in_string = false;
            var escaped = false;
            var depth: i32 = 0;
            
            while (pos < input.len) {
                // Find safe split point
                var safe_pos = pos;
                while (safe_pos < input.len) {
                    const c = input[safe_pos];
                    
                    if (escaped) {
                        escaped = false;
                    } else if (in_string) {
                        if (c == '\\') {
                            escaped = true;
                        } else if (c == '"') {
                            in_string = false;
                        }
                    } else {
                        switch (c) {
                            '"' => in_string = true,
                            '{', '[' => depth += 1,
                            '}', ']' => {
                                depth -= 1;
                                if (depth == 0 and safe_pos > pos) {
                                    // Good split point after closing bracket at depth 0
                                    boundaries.append(safe_pos + 1) catch unreachable;
                                    pos = safe_pos + 1 + target_chunk_size;
                                    break;
                                }
                            },
                            ',' => {
                                if (depth == 0 and safe_pos > pos) {
                                    // Good split point after comma at depth 0
                                    boundaries.append(safe_pos + 1) catch unreachable;
                                    pos = safe_pos + 1 + target_chunk_size;
                                    break;
                                }
                            },
                            else => {},
                        }
                    }
                    
                    safe_pos += 1;
                }
                
                if (safe_pos >= input.len) break;
            }
        }
        
        return ChunkInfo{
            .chunk_count = boundaries.items.len,
            .chunk_boundaries = boundaries.toOwnedSlice() catch unreachable,
        };
    }
    
    fn mergeResults(_: *TurboMinifierParallelV2, work_items: []optimized_work_stealing.OptimizedWorkStealer.WorkItem, output: []u8) !usize {
        var total_output: usize = 0;
        
        for (work_items) |*item| {
            const output_size = item.output_size.load(.acquire);
            
            if (total_output + output_size > output.len) {
                return error.OutputBufferTooSmall;
            }
            
            @memcpy(output[total_output..total_output + output_size], item.output[0..output_size]);
            total_output += output_size;
        }
        
        return total_output;
    }
    
    pub fn getPerformanceStats(self: *TurboMinifierParallelV2) PerformanceStats {
        const local_hits = self.work_stealer.local_hits.load(.acquire);
        const steal_success = self.work_stealer.steal_success.load(.acquire);
        const steal_attempts = self.work_stealer.steal_attempts.load(.acquire);
        
        const work_steal_ratio = if (steal_attempts > 0)
            @as(f64, @floatFromInt(steal_success)) / @as(f64, @floatFromInt(steal_attempts))
        else
            0.0;
            
        const total_work = local_hits + steal_success;
        const thread_efficiency = if (total_work > 0)
            @as(f64, @floatFromInt(total_work)) / (@as(f64, @floatFromInt(self.worker_threads.len)) * @as(f64, @floatFromInt(self.total_chunks_processed.load(.acquire))))
        else
            0.0;
            
        return PerformanceStats{
            .total_bytes_processed = self.total_bytes_processed.load(.acquire),
            .total_processing_time = self.total_processing_time.load(.acquire),
            .total_chunks_processed = self.total_chunks_processed.load(.acquire),
            .work_steal_ratio = work_steal_ratio,
            .thread_efficiency = thread_efficiency,
            .local_hit_rate = @as(f64, @floatFromInt(local_hits)) / @as(f64, @floatFromInt(total_work)),
        };
    }
    
    const PerformanceStats = struct {
        total_bytes_processed: u64,
        total_processing_time: u64,
        total_chunks_processed: u64,
        work_steal_ratio: f64,
        thread_efficiency: f64,
        local_hit_rate: f64,
    };
    
    fn getNumaNodeCount() u8 {
        // Simplified - in real implementation would query system
        return 1;
    }
};