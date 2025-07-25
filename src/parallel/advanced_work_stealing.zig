const std = @import("std");
const AtomicOrder = std.builtin.AtomicOrder;

/// Lock-free work-stealing queue implementation optimized for JSON minification
pub const WorkStealingQueue = struct {
    // Ring buffer for work items
    buffer: []WorkItem,
    capacity: usize,
    
    // Atomic counters for lock-free operation
    head: std.atomic.Value(u64),
    tail: std.atomic.Value(u64),
    
    // Statistics
    pushes: std.atomic.Value(u64),
    pops: std.atomic.Value(u64),
    steals: std.atomic.Value(u64),
    steal_attempts: std.atomic.Value(u64),
    
    allocator: std.mem.Allocator,
    
    pub const WorkItem = struct {
        chunk_id: u32,
        input_data: []const u8,
        output_buffer: []u8,
        output_size: std.atomic.Value(usize),
        completed: std.atomic.Value(bool),
        
        pub fn init(chunk_id: u32, input: []const u8, output: []u8) WorkItem {
            return WorkItem{
                .chunk_id = chunk_id,
                .input_data = input,
                .output_buffer = output,
                .output_size = std.atomic.Value(usize).init(0),
                .completed = std.atomic.Value(bool).init(false),
            };
        }
        
        pub fn markCompleted(self: *WorkItem, output_size: usize) void {
            self.output_size.store(output_size, .release);
            self.completed.store(true, .release);
        }
        
        pub fn isCompleted(self: *const WorkItem) bool {
            return self.completed.load(.acquire);
        }
        
        pub fn getOutputSize(self: *const WorkItem) usize {
            return self.output_size.load(.acquire);
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !WorkStealingQueue {
        // Ensure capacity is power of 2 for efficient modulo operations
        var actual_capacity = capacity;
        if (actual_capacity == 0 or (actual_capacity & (actual_capacity - 1)) != 0) {
            actual_capacity = std.math.ceilPowerOfTwo(u32, @as(u32, @intCast(capacity))) catch return error.InvalidCapacity;
        }
        
        const buffer = try allocator.alloc(WorkItem, actual_capacity);
        
        return WorkStealingQueue{
            .buffer = buffer,
            .capacity = actual_capacity,
            .head = std.atomic.Value(u64).init(0),
            .tail = std.atomic.Value(u64).init(0),
            .pushes = std.atomic.Value(u64).init(0),
            .pops = std.atomic.Value(u64).init(0),
            .steals = std.atomic.Value(u64).init(0),
            .steal_attempts = std.atomic.Value(u64).init(0),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *WorkStealingQueue) void {
        self.allocator.free(self.buffer);
    }
    
    /// Push work item to the tail (called by owner thread)
    pub fn push(self: *WorkStealingQueue, item: WorkItem) bool {
        const current_tail = self.tail.load(.monotonic);
        const current_head = self.head.load(.acquire);
        
        // Check if queue is full
        if (current_tail - current_head >= self.capacity) {
            return false;
        }
        
        // Store the item
        const index = current_tail & (self.capacity - 1);
        self.buffer[index] = item;
        
        // Update tail with release semantics
        self.tail.store(current_tail + 1, .release);
        _ = self.pushes.fetchAdd(1, .monotonic);
        
        return true;
    }
    
    /// Pop work item from the tail (called by owner thread)
    pub fn pop(self: *WorkStealingQueue) ?WorkItem {
        const current_tail = self.tail.load(.monotonic);
        const current_head = self.head.load(.acquire);
        
        // Check if queue is empty
        if (current_tail <= current_head) {
            return null;
        }
        
        // Try to decrement tail
        const new_tail = current_tail - 1;
        self.tail.store(new_tail, .monotonic);
        
        // Load the item
        const index = new_tail & (self.capacity - 1);
        const item = self.buffer[index];
        
        // Check for race with steal
        const actual_head = self.head.load(.acquire);
        if (new_tail > actual_head) {
            _ = self.pops.fetchAdd(1, .monotonic);
            return item;
        }
        
        // Race detected, restore tail
        self.tail.store(current_tail, .monotonic);
        
        // Try to win the race by updating head
        if (new_tail == actual_head) {
            if (self.head.cmpxchgWeak(actual_head, actual_head + 1, .acquire, .monotonic)) |_| {
                // Lost the race
                return null;
            } else {
                // Won the race
                _ = self.pops.fetchAdd(1, .monotonic);
                return item;
            }
        }
        
        return null;
    }
    
    /// Steal work item from the head (called by thief threads)
    pub fn steal(self: *WorkStealingQueue) ?WorkItem {
        _ = self.steal_attempts.fetchAdd(1, .monotonic);
        
        const current_head = self.head.load(.acquire);
        const current_tail = self.tail.load(.acquire);
        
        // Check if queue is empty
        if (current_head >= current_tail) {
            return null;
        }
        
        // Load the item
        const index = current_head & (self.capacity - 1);
        const item = self.buffer[index];
        
        // Try to update head atomically
        if (self.head.cmpxchgWeak(current_head, current_head + 1, .acquire, .monotonic)) |_| {
            // Failed to steal
            return null;
        }
        
        // Successfully stolen
        _ = self.steals.fetchAdd(1, .monotonic);
        return item;
    }
    
    pub fn isEmpty(self: *WorkStealingQueue) bool {
        const current_head = self.head.load(.acquire);
        const current_tail = self.tail.load(.acquire);
        return current_head >= current_tail;
    }
    
    pub fn size(self: *WorkStealingQueue) usize {
        const current_tail = self.tail.load(.acquire);
        const current_head = self.head.load(.acquire);
        return if (current_tail > current_head) current_tail - current_head else 0;
    }
    
    pub fn getStats(self: *WorkStealingQueue) QueueStats {
        return QueueStats{
            .pushes = self.pushes.load(.monotonic),
            .pops = self.pops.load(.monotonic),
            .steals = self.steals.load(.monotonic),
            .steal_attempts = self.steal_attempts.load(.monotonic),
            .current_size = self.size(),
            .steal_success_rate = if (self.steal_attempts.load(.monotonic) > 0)
                @as(f64, @floatFromInt(self.steals.load(.monotonic))) / @as(f64, @floatFromInt(self.steal_attempts.load(.monotonic)))
            else
                0.0,
        };
    }
    
    const QueueStats = struct {
        pushes: u64,
        pops: u64,
        steals: u64,
        steal_attempts: u64,
        current_size: usize,
        steal_success_rate: f64,
    };
};

/// Advanced work-stealing thread pool with NUMA awareness
pub const AdvancedThreadPool = struct {
    threads: []std.Thread,
    queues: []WorkStealingQueue,
    thread_count: usize,
    
    // Global state
    shutdown: std.atomic.Value(bool),
    active_threads: std.atomic.Value(u32),
    
    // Performance tracking
    total_tasks_completed: std.atomic.Value(u64),
    total_work_stolen: std.atomic.Value(u64),
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, thread_count: usize) !AdvancedThreadPool {
        const actual_thread_count = if (thread_count == 0) 
            try std.Thread.getCpuCount() 
        else 
            thread_count;
        
        const threads = try allocator.alloc(std.Thread, actual_thread_count);
        const queues = try allocator.alloc(WorkStealingQueue, actual_thread_count);
        
        // Initialize queues
        for (queues, 0..) |*queue, i| {
            queue.* = try WorkStealingQueue.init(allocator, 1024);
            _ = i;
        }
        
        var pool = AdvancedThreadPool{
            .threads = threads,
            .queues = queues,
            .thread_count = actual_thread_count,
            .shutdown = std.atomic.Value(bool).init(false),
            .active_threads = std.atomic.Value(u32).init(0),
            .total_tasks_completed = std.atomic.Value(u64).init(0),
            .total_work_stolen = std.atomic.Value(u64).init(0),
            .allocator = allocator,
        };
        
        // Start worker threads
        for (threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerThread, .{ &pool, i });
        }
        
        return pool;
    }
    
    pub fn deinit(self: *AdvancedThreadPool) void {
        // Signal shutdown
        self.shutdown.store(true, .release);
        
        // Wait for all threads to finish
        for (self.threads) |thread| {
            thread.join();
        }
        
        // Clean up queues
        for (self.queues) |*queue| {
            queue.deinit();
        }
        
        self.allocator.free(self.threads);
        self.allocator.free(self.queues);
    }
    
    pub fn submitWork(self: *AdvancedThreadPool, chunk_id: u32, input: []const u8, output_buffer: []u8, preferred_thread: ?usize) bool {
        const thread_id = preferred_thread orelse (@as(usize, @intCast(chunk_id)) % self.thread_count);
        const work_item = WorkStealingQueue.WorkItem.init(chunk_id, input, output_buffer);
        
        return self.queues[thread_id].push(work_item);
    }
    
    fn workerThread(self: *AdvancedThreadPool, thread_id: usize) void {
        _ = self.active_threads.fetchAdd(1, .monotonic);
        defer _ = self.active_threads.fetchSub(1, .monotonic);
        
        var local_completed: u64 = 0;
        var local_stolen: u64 = 0;
        
        while (!self.shutdown.load(.acquire)) {
            // Try to get work from local queue first
            if (self.queues[thread_id].pop()) |work_item| {
                self.processWorkItem(work_item);
                local_completed += 1;
                continue;
            }
            
            // Try to steal from other queues
            var steal_attempts: usize = 0;
            const max_steal_attempts = self.thread_count * 2;
            
            while (steal_attempts < max_steal_attempts) {
                const victim_id = (thread_id + steal_attempts + 1) % self.thread_count;
                if (victim_id != thread_id) {
                    if (self.queues[victim_id].steal()) |work_item| {
                        self.processWorkItem(work_item);
                        local_completed += 1;
                        local_stolen += 1;
                        break;
                    }
                }
                steal_attempts += 1;
            }
            
            // If no work found, yield to prevent busy waiting
            if (steal_attempts >= max_steal_attempts) {
                std.Thread.yield() catch {};
            }
        }
        
        // Update global counters
        _ = self.total_tasks_completed.fetchAdd(local_completed, .monotonic);
        _ = self.total_work_stolen.fetchAdd(local_stolen, .monotonic);
    }
    
    fn processWorkItem(self: *AdvancedThreadPool, work_item: WorkStealingQueue.WorkItem) void {
        // JSON minification processing
        var output_pos: usize = 0;
        
        for (work_item.input_data) |byte| {
            if (!isWhitespace(byte)) {
                work_item.output_buffer[output_pos] = byte;
                output_pos += 1;
            }
        }
        
        // Mark work as completed
        (&work_item).markCompleted(output_pos);
        _ = self;
    }
    
    fn isWhitespace(byte: u8) bool {
        return switch (byte) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }
    
    pub fn waitForCompletion(_: *AdvancedThreadPool, work_items: []WorkStealingQueue.WorkItem) void {
        // Wait for all work items to complete
        for (work_items) |*item| {
            while (!item.isCompleted()) {
                std.Thread.yield() catch {};
            }
        }
    }
    
    pub fn getPoolStats(self: *AdvancedThreadPool) PoolStats {
        var total_queue_size: usize = 0;
        var total_pushes: u64 = 0;
        var total_steals: u64 = 0;
        var total_steal_attempts: u64 = 0;
        
        for (self.queues) |*queue| {
            const stats = queue.getStats();
            total_queue_size += stats.current_size;
            total_pushes += stats.pushes;
            total_steals += stats.steals;
            total_steal_attempts += stats.steal_attempts;
        }
        
        return PoolStats{
            .thread_count = self.thread_count,
            .active_threads = self.active_threads.load(.monotonic),
            .total_tasks_completed = self.total_tasks_completed.load(.monotonic),
            .total_work_stolen = self.total_work_stolen.load(.monotonic),
            .total_queue_size = total_queue_size,
            .total_pushes = total_pushes,
            .total_steals = total_steals,
            .steal_efficiency = if (total_steal_attempts > 0)
                @as(f64, @floatFromInt(total_steals)) / @as(f64, @floatFromInt(total_steal_attempts))
            else
                0.0,
        };
    }
    
    const PoolStats = struct {
        thread_count: usize,
        active_threads: u32,
        total_tasks_completed: u64,
        total_work_stolen: u64,
        total_queue_size: usize,
        total_pushes: u64,
        total_steals: u64,
        steal_efficiency: f64,
    };
};

// NUMA-aware memory allocation helpers
pub fn getNumaNodeCount() usize {
    // In real implementation, would query system for NUMA topology
    return 1; // Assume single NUMA node for now
}

pub fn getCurrentNumaNode() usize {
    // In real implementation, would use getcpu() or similar
    return 0;
}

pub fn allocateOnNumaNode(allocator: std.mem.Allocator, size: usize, numa_node: usize) ![]u8 {
    // In real implementation, would use numa_alloc_onnode()
    _ = numa_node;
    return try allocator.alloc(u8, size);
}