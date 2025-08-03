//! Common Work-Stealing Queue Abstraction
//!
//! This module provides a reusable work-stealing queue implementation
//! that can be used across different parallel processing scenarios.

const std = @import("std");
const builtin = @import("builtin");
const constants = @import("constants.zig");

/// Generic work item interface
pub const WorkItem = struct {
    /// Unique identifier
    id: u64,
    
    /// Priority (higher = more important)
    priority: u8 = 128,
    
    /// User data pointer
    data: *anyopaque,
    
    /// Function to execute
    execute_fn: *const fn (data: *anyopaque) anyerror!void,
    
    /// Completion status
    completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    
    pub fn execute(self: *WorkItem) !void {
        try self.execute_fn(self.data);
        self.completed.store(true, .release);
    }
    
    pub fn isCompleted(self: *const WorkItem) bool {
        return self.completed.load(.acquire);
    }
};

/// Thread-local work queue with stealing support
pub const LocalQueue = struct {
    /// Ring buffer of work items
    buffer: []WorkItem,
    
    /// Capacity (must be power of 2)
    capacity: usize,
    
    /// Head index (steal from here)
    head: std.atomic.Value(u64),
    
    /// Tail index (push/pop from here)
    tail: std.atomic.Value(u64),
    
    /// Owner thread ID
    owner_thread: std.Thread.Id,
    
    /// Statistics
    stats: QueueStats,
    
    /// Allocator
    allocator: std.mem.Allocator,
    
    /// Cache line padding to prevent false sharing
    _padding: [constants.System.CACHE_LINE_SIZE - @sizeOf(std.Thread.Id)]u8 = undefined,
    
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !LocalQueue {
        // Ensure power of 2 for efficient modulo
        const actual_capacity = try std.math.ceilPowerOfTwo(usize, capacity);
        
        return LocalQueue{
            .buffer = try allocator.alloc(WorkItem, actual_capacity),
            .capacity = actual_capacity,
            .head = std.atomic.Value(u64).init(0),
            .tail = std.atomic.Value(u64).init(0),
            .owner_thread = std.Thread.getCurrentId(),
            .stats = QueueStats{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *LocalQueue) void {
        self.allocator.free(self.buffer);
    }
    
    /// Push work item (called by owner thread)
    pub fn push(self: *LocalQueue, item: WorkItem) bool {
        const current_tail = self.tail.load(.monotonic);
        const current_head = self.head.load(.acquire);
        
        // Check if full
        if (current_tail - current_head >= self.capacity) {
            self.stats.push_failures += 1;
            return false;
        }
        
        // Store item
        self.buffer[current_tail & (self.capacity - 1)] = item;
        self.tail.store(current_tail + 1, .release);
        
        self.stats.pushes += 1;
        return true;
    }
    
    /// Pop work item (called by owner thread)
    pub fn pop(self: *LocalQueue) ?WorkItem {
        var current_tail = self.tail.load(.monotonic);
        if (current_tail == 0) return null;
        
        current_tail -= 1;
        self.tail.store(current_tail, .monotonic);
        
        const current_head = self.head.load(.acquire);
        
        if (current_tail < current_head) {
            self.tail.store(current_head, .monotonic);
            return null;
        }
        
        const item = self.buffer[current_tail & (self.capacity - 1)];
        
        if (current_tail == current_head) {
            // Last item - need CAS to prevent concurrent steal
            if (self.head.cmpxchgWeak(
                current_head,
                current_head + 1,
                .seq_cst,
                .seq_cst,
            ) != null) {
                // Lost race to stealer
                self.tail.store(current_head + 1, .monotonic);
                return null;
            }
            self.tail.store(current_head + 1, .monotonic);
        }
        
        self.stats.pops += 1;
        return item;
    }
    
    /// Steal work item (called by other threads)
    pub fn steal(self: *LocalQueue) ?WorkItem {
        while (true) {
            const current_head = self.head.load(.acquire);
            const current_tail = self.tail.load(.acquire);
            
            if (current_head >= current_tail) {
                return null; // Empty
            }
            
            const item = self.buffer[current_head & (self.capacity - 1)];
            
            // Try to increment head
            if (self.head.cmpxchgWeak(
                current_head,
                current_head + 1,
                .seq_cst,
                .seq_cst,
            )) |_| {
                // CAS failed, retry
                continue;
            }
            
            self.stats.steals += 1;
            return item;
        }
    }
    
    /// Get approximate size
    pub fn size(self: *const LocalQueue) usize {
        const tail = self.tail.load(.monotonic);
        const head = self.head.load(.monotonic);
        return if (tail >= head) tail - head else 0;
    }
    
    /// Check if empty
    pub fn isEmpty(self: *const LocalQueue) bool {
        return self.size() == 0;
    }
};

/// Queue statistics
pub const QueueStats = struct {
    pushes: u64 = 0,
    push_failures: u64 = 0,
    pops: u64 = 0,
    steals: u64 = 0,
    
    pub fn getEfficiency(self: *const QueueStats) f64 {
        const total_ops = self.pushes + self.pops + self.steals;
        if (total_ops == 0) return 0;
        return @as(f64, @floatFromInt(self.pops)) / @as(f64, @floatFromInt(total_ops));
    }
};

/// Work-stealing scheduler
pub const WorkStealingScheduler = struct {
    /// Per-thread queues
    queues: []LocalQueue,
    
    /// Thread pool
    threads: []std.Thread,
    
    /// Global termination flag
    should_stop: std.atomic.Value(bool),
    
    /// Active thread count
    active_threads: std.atomic.Value(u32),
    
    /// Random number generators for stealing
    rngs: []std.Random.DefaultPrng,
    
    /// Configuration
    config: SchedulerConfig,
    
    /// Allocator
    allocator: std.mem.Allocator,
    
    pub const SchedulerConfig = struct {
        /// Number of worker threads
        thread_count: usize = 0, // 0 = auto-detect
        
        /// Queue capacity per thread
        queue_capacity: usize = 1024,
        
        /// Stealing strategy
        steal_strategy: StealStrategy = .random,
        
        /// Maximum steal attempts before sleeping
        max_steal_attempts: u32 = constants.ThreadPool.STEAL_ATTEMPTS,
        
        /// Sleep duration when no work (microseconds)
        idle_sleep_us: u32 = 10,
    };
    
    pub const StealStrategy = enum {
        /// Random victim selection
        random,
        
        /// Round-robin victim selection
        round_robin,
        
        /// Nearest neighbor first
        nearest_neighbor,
        
        /// Work-guided (steal from busiest)
        work_guided,
    };
    
    pub fn init(allocator: std.mem.Allocator, config: SchedulerConfig) !WorkStealingScheduler {
        const thread_count = if (config.thread_count == 0)
            try std.Thread.getCpuCount()
        else
            config.thread_count;
        
        var self = WorkStealingScheduler{
            .queues = try allocator.alloc(LocalQueue, thread_count),
            .threads = try allocator.alloc(std.Thread, thread_count),
            .should_stop = std.atomic.Value(bool).init(false),
            .active_threads = std.atomic.Value(u32).init(0),
            .rngs = try allocator.alloc(std.Random.DefaultPrng, thread_count),
            .config = config,
            .allocator = allocator,
        };
        
        // Initialize queues and RNGs
        for (0..thread_count) |i| {
            self.queues[i] = try LocalQueue.init(allocator, config.queue_capacity);
            self.rngs[i] = std.Random.DefaultPrng.init(@as(u64, @intCast(i)) + @as(u64, @intCast(std.time.timestamp())));
        }
        
        return self;
    }
    
    pub fn deinit(self: *WorkStealingScheduler) void {
        // Stop all threads
        self.stop();
        
        // Clean up queues
        for (self.queues) |*queue| {
            queue.deinit();
        }
        
        // Free arrays
        self.allocator.free(self.queues);
        self.allocator.free(self.threads);
        self.allocator.free(self.rngs);
    }
    
    /// Start worker threads
    pub fn start(self: *WorkStealingScheduler) !void {
        self.should_stop.store(false, .release);
        
        for (self.threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerLoop, .{ self, i });
        }
    }
    
    /// Stop all worker threads
    pub fn stop(self: *WorkStealingScheduler) void {
        self.should_stop.store(true, .release);
        
        for (self.threads) |thread| {
            thread.join();
        }
    }
    
    /// Submit work to a specific thread
    pub fn submitTo(self: *WorkStealingScheduler, thread_id: usize, item: WorkItem) bool {
        if (thread_id >= self.queues.len) return false;
        return self.queues[thread_id].push(item);
    }
    
    /// Submit work to least loaded thread
    pub fn submit(self: *WorkStealingScheduler, item: WorkItem) bool {
        var min_size = std.math.maxInt(usize);
        var best_queue: usize = 0;
        
        // Find least loaded queue
        for (self.queues, 0..) |*queue, i| {
            const size = queue.size();
            if (size < min_size) {
                min_size = size;
                best_queue = i;
            }
        }
        
        return self.queues[best_queue].push(item);
    }
    
    /// Worker thread main loop
    fn workerLoop(self: *WorkStealingScheduler, thread_id: usize) void {
        const queue = &self.queues[thread_id];
        var rng = &self.rngs[thread_id];
        var consecutive_failures: u32 = 0;
        
        _ = self.active_threads.fetchAdd(1, .monotonic);
        defer _ = self.active_threads.fetchSub(1, .monotonic);
        
        while (!self.should_stop.load(.acquire)) {
            // Try to get work from local queue
            if (queue.pop()) |item| {
                var work_item = item;
                work_item.execute() catch |err| {
                    std.log.err("Work item {} failed: {}", .{ work_item.id, err });
                };
                consecutive_failures = 0;
                continue;
            }
            
            // Local queue empty, try stealing
            if (self.trySteal(thread_id, rng)) |item| {
                var work_item = item;
                work_item.execute() catch |err| {
                    std.log.err("Work item {} failed: {}", .{ work_item.id, err });
                };
                consecutive_failures = 0;
                continue;
            }
            
            // No work found
            consecutive_failures += 1;
            
            if (consecutive_failures > self.config.max_steal_attempts) {
                // Sleep briefly to reduce CPU usage
                std.time.sleep(self.config.idle_sleep_us * 1000);
                consecutive_failures = 0;
            }
        }
    }
    
    /// Try to steal work from other threads
    fn trySteal(self: *WorkStealingScheduler, thread_id: usize, rng: *std.Random.DefaultPrng) ?WorkItem {
        const thread_count = self.queues.len;
        
        switch (self.config.steal_strategy) {
            .random => {
                // Try random victims
                for (0..self.config.max_steal_attempts) |_| {
                    const victim = rng.random().intRangeAtMost(usize, 0, thread_count - 1);
                    if (victim == thread_id) continue;
                    
                    if (self.queues[victim].steal()) |item| {
                        return item;
                    }
                }
            },
            .round_robin => {
                // Try all queues in order
                for (1..thread_count) |offset| {
                    const victim = (thread_id + offset) % thread_count;
                    if (self.queues[victim].steal()) |item| {
                        return item;
                    }
                }
            },
            .nearest_neighbor => {
                // Try adjacent threads first
                for (1..thread_count) |distance| {
                    // Try left neighbor
                    if (distance <= thread_id) {
                        const victim = thread_id - distance;
                        if (self.queues[victim].steal()) |item| {
                            return item;
                        }
                    }
                    
                    // Try right neighbor
                    const right = thread_id + distance;
                    if (right < thread_count) {
                        if (self.queues[right].steal()) |item| {
                            return item;
                        }
                    }
                }
            },
            .work_guided => {
                // Find busiest queue
                var max_size: usize = 0;
                var busiest: ?usize = null;
                
                for (self.queues, 0..) |*queue, i| {
                    if (i == thread_id) continue;
                    const size = queue.size();
                    if (size > max_size) {
                        max_size = size;
                        busiest = i;
                    }
                }
                
                if (busiest) |victim| {
                    return self.queues[victim].steal();
                }
            },
        }
        
        return null;
    }
    
    /// Get total pending work items
    pub fn getPendingWork(self: *const WorkStealingScheduler) usize {
        var total: usize = 0;
        for (self.queues) |*queue| {
            total += queue.size();
        }
        return total;
    }
    
    /// Get scheduler statistics
    pub fn getStats(self: *const WorkStealingScheduler) SchedulerStats {
        var stats = SchedulerStats{};
        
        for (self.queues) |*queue| {
            stats.total_pushes += queue.stats.pushes;
            stats.total_push_failures += queue.stats.push_failures;
            stats.total_pops += queue.stats.pops;
            stats.total_steals += queue.stats.steals;
        }
        
        stats.active_threads = self.active_threads.load(.monotonic);
        stats.pending_work = self.getPendingWork();
        
        return stats;
    }
};

/// Scheduler statistics
pub const SchedulerStats = struct {
    total_pushes: u64 = 0,
    total_push_failures: u64 = 0,
    total_pops: u64 = 0,
    total_steals: u64 = 0,
    active_threads: u32 = 0,
    pending_work: usize = 0,
    
    pub fn getStealRate(self: *const SchedulerStats) f64 {
        const total = self.total_pops + self.total_steals;
        if (total == 0) return 0;
        return @as(f64, @floatFromInt(self.total_steals)) / @as(f64, @floatFromInt(total));
    }
    
    pub fn format(
        self: SchedulerStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print(
            "Pushes: {}, Pops: {}, Steals: {} ({d:.1}%), Active: {}, Pending: {}",
            .{
                self.total_pushes,
                self.total_pops,
                self.total_steals,
                self.getStealRate() * 100,
                self.active_threads,
                self.pending_work,
            },
        );
    }
};

// Tests
test "LocalQueue basic operations" {
    var queue = try LocalQueue.init(std.testing.allocator, 16);
    defer queue.deinit();
    
    const TestData = struct { value: u32 };
    var data1 = TestData{ .value = 42 };
    
    const item1 = WorkItem{
        .id = 1,
        .data = @ptrCast(&data1),
        .execute_fn = struct {
            fn execute(data: *anyopaque) !void {
                const test_data: *TestData = @ptrCast(@alignCast(data));
                test_data.value += 1;
            }
        }.execute,
    };
    
    // Push and pop
    try std.testing.expect(queue.push(item1));
    const popped = queue.pop();
    try std.testing.expect(popped != null);
    try std.testing.expectEqual(@as(u64, 1), popped.?.id);
}

test "Work stealing" {
    var queue1 = try LocalQueue.init(std.testing.allocator, 16);
    defer queue1.deinit();
    
    var queue2 = try LocalQueue.init(std.testing.allocator, 16);
    defer queue2.deinit();
    
    // Push to queue1
    const item = WorkItem{
        .id = 1,
        .data = undefined,
        .execute_fn = struct {
            fn execute(data: *anyopaque) !void {
                _ = data;
            }
        }.execute,
    };
    
    try std.testing.expect(queue1.push(item));
    
    // Steal from queue2's perspective
    const stolen = queue1.steal();
    try std.testing.expect(stolen != null);
    try std.testing.expectEqual(@as(u64, 1), stolen.?.id);
}