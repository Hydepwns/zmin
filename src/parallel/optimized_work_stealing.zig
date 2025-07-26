// Optimized Work-Stealing Implementation for JSON Minification
// Target: 50%+ thread efficiency through better work distribution

const std = @import("std");
const builtin = @import("builtin");

/// Optimized work-stealing scheduler with improved efficiency
pub const OptimizedWorkStealer = struct {
    // Per-thread work queues
    local_queues: []LocalQueue,
    thread_count: usize,
    
    // Global work queue for initial distribution
    global_queue: GlobalQueue,
    
    // Scheduling hints
    chunk_affinity: []u8, // Which thread processed which chunk last
    hot_threads: std.atomic.Value(u64), // Bitmask of threads with work
    
    // Performance tracking
    local_hits: std.atomic.Value(u64),
    steal_success: std.atomic.Value(u64),
    steal_attempts: std.atomic.Value(u64),
    
    allocator: std.mem.Allocator,
    
    // Pointer-based work submission and retrieval
    local_queues_ptr: []LocalQueuePtr = &[_]LocalQueuePtr{},
    global_queue_ptr: GlobalQueuePtr = undefined,
    
    const LocalQueue = struct {
        // Double-ended queue for efficient push/pop from owner, steal from others
        items: []WorkItem,
        capacity: usize,
        head: std.atomic.Value(u32),
        tail: std.atomic.Value(u32),
        
        // Cache-line padding to prevent false sharing
        _padding: [64 - @sizeOf(std.atomic.Value(u32)) * 2]u8 = undefined,
        
        pub fn init(allocator: std.mem.Allocator, capacity: usize) !LocalQueue {
            return LocalQueue{
                .items = try allocator.alloc(WorkItem, capacity),
                .capacity = capacity,
                .head = std.atomic.Value(u32).init(0),
                .tail = std.atomic.Value(u32).init(0),
            };
        }
        
        pub fn deinit(self: *LocalQueue, allocator: std.mem.Allocator) void {
            allocator.free(self.items);
        }
        
        // Owner thread operations (no synchronization needed)
        pub fn pushLocal(self: *LocalQueue, item: WorkItem) bool {
            const tail = self.tail.load(.monotonic);
            const head = self.head.load(.acquire);
            
            if (tail - head >= self.capacity) {
                return false; // Queue full
            }
            
            self.items[tail % self.capacity] = item;
            self.tail.store(tail + 1, .release);
            return true;
        }
        
        pub fn popLocal(self: *LocalQueue) ?WorkItem {
            const tail = self.tail.load(.monotonic) - 1;
            self.tail.store(tail, .monotonic);
            
            const head = self.head.load(.acquire);
            if (tail < head) {
                self.tail.store(head, .monotonic);
                return null;
            }
            
            const item = self.items[tail % self.capacity];
            
            if (tail == head) {
                // Last item - need to synchronize with stealers
                if (self.head.cmpxchgWeak(head, head + 1, .acquire, .monotonic) != null) {
                    // Lost race with stealer
                    self.tail.store(head + 1, .monotonic);
                    return null;
                }
                self.tail.store(head + 1, .monotonic);
            }
            
            return item;
        }
        
        // Stealer thread operations
        pub fn steal(self: *LocalQueue) ?WorkItem {
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);
            
            if (head >= tail) {
                return null;
            }
            
            const item = self.items[head % self.capacity];
            
            if (self.head.cmpxchgWeak(head, head + 1, .acquire, .monotonic) != null) {
                // Failed to steal
                return null;
            }
            
            return item;
        }
        
        pub fn size(self: *LocalQueue) u32 {
            const tail = self.tail.load(.acquire);
            const head = self.head.load(.acquire);
            return if (tail > head) tail - head else 0;
        }
    };
    
    const GlobalQueue = struct {
        items: std.ArrayList(WorkItem),
        mutex: std.Thread.Mutex,
        
        pub fn init(allocator: std.mem.Allocator) GlobalQueue {
            return GlobalQueue{
                .items = std.ArrayList(WorkItem).init(allocator),
                .mutex = .{},
            };
        }
        
        pub fn deinit(self: *GlobalQueue) void {
            self.items.deinit();
        }
        
        pub fn push(self: *GlobalQueue, item: WorkItem) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.append(item);
        }
        
        pub fn pop(self: *GlobalQueue) ?WorkItem {
            self.mutex.lock();
            defer self.mutex.unlock();
            return if (self.items.items.len > 0) self.items.pop() else null;
        }
        
        pub fn empty(self: *GlobalQueue) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len == 0;
        }
    };
    
    pub const WorkItem = struct {
        chunk_id: u32,
        input: []const u8,
        output: []u8,
        priority: u8, // Higher priority for larger chunks
        numa_node: u8,
        
        // Results
        output_size: std.atomic.Value(u32),
        completed: std.atomic.Value(bool),
        
        pub fn init(chunk_id: u32, input: []const u8, output: []u8, priority: u8, numa_node: u8) WorkItem {
            return WorkItem{
                .chunk_id = chunk_id,
                .input = input,
                .output = output,
                .priority = priority,
                .numa_node = numa_node,
                .output_size = std.atomic.Value(u32).init(0),
                .completed = std.atomic.Value(bool).init(false),
            };
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, thread_count: usize) !OptimizedWorkStealer {
        const local_queues = try allocator.alloc(LocalQueue, thread_count);
        errdefer allocator.free(local_queues);
        
        for (local_queues) |*queue| {
            queue.* = try LocalQueue.init(allocator, 1024);
        }
        
        const chunk_affinity = try allocator.alloc(u8, 1024); // Support up to 1024 chunks
        @memset(chunk_affinity, 0xFF); // No affinity initially
        
        var result = OptimizedWorkStealer{
            .local_queues = local_queues,
            .thread_count = thread_count,
            .global_queue = GlobalQueue.init(allocator),
            .chunk_affinity = chunk_affinity,
            .hot_threads = std.atomic.Value(u64).init(0),
            .local_hits = std.atomic.Value(u64).init(0),
            .steal_success = std.atomic.Value(u64).init(0),
            .steal_attempts = std.atomic.Value(u64).init(0),
            .allocator = allocator,
            .local_queues_ptr = &[_]LocalQueuePtr{},
            .global_queue_ptr = undefined,
        };
        
        // Initialize pointer queues
        try result.initPtrQueues();
        
        return result;
    }
    
    pub fn deinit(self: *OptimizedWorkStealer) void {
        for (self.local_queues) |*queue| {
            queue.deinit(self.allocator);
        }
        self.allocator.free(self.local_queues);
        self.allocator.free(self.chunk_affinity);
        self.global_queue.deinit();
        
        // Clean up pointer queues if initialized
        self.deinitPtrQueues();
    }
    
    // New pointer-based queue for fixed implementation
    const LocalQueuePtr = struct {
        items: []*WorkItem,
        capacity: usize,
        head: std.atomic.Value(u32),
        tail: std.atomic.Value(u32),
        
        pub fn init(allocator: std.mem.Allocator, capacity: usize) !LocalQueuePtr {
            return LocalQueuePtr{
                .items = try allocator.alloc(*WorkItem, capacity),
                .capacity = capacity,
                .head = std.atomic.Value(u32).init(0),
                .tail = std.atomic.Value(u32).init(0),
            };
        }
        
        pub fn deinit(self: *LocalQueuePtr, allocator: std.mem.Allocator) void {
            allocator.free(self.items);
        }
        
        pub fn pushLocal(self: *LocalQueuePtr, item: *WorkItem) bool {
            const tail = self.tail.load(.monotonic);
            const head = self.head.load(.acquire);
            
            if (tail - head >= self.capacity) {
                return false;
            }
            
            self.items[tail % self.capacity] = item;
            self.tail.store(tail + 1, .release);
            return true;
        }
        
        pub fn popLocal(self: *LocalQueuePtr) ?*WorkItem {
            const tail = self.tail.load(.monotonic) - 1;
            self.tail.store(tail, .monotonic);
            
            const head = self.head.load(.acquire);
            if (tail < head) {
                self.tail.store(head, .monotonic);
                return null;
            }
            
            const item = self.items[tail % self.capacity];
            
            if (tail == head) {
                self.tail.store(head + 1, .monotonic);
                const old_head = self.head.cmpxchgWeak(head, head + 1, .acquire, .monotonic);
                if (old_head == null) {
                    return item;
                }
                return null;
            }
            
            return item;
        }
        
        pub fn steal(self: *LocalQueuePtr) ?*WorkItem {
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);
            
            if (head >= tail) {
                return null;
            }
            
            const item = self.items[head % self.capacity];
            
            if (self.head.cmpxchgWeak(head, head + 1, .acquire, .monotonic) != null) {
                return null;
            }
            
            return item;
        }
    };
    
    // Global queue for pointers
    const GlobalQueuePtr = struct {
        items: std.ArrayList(*WorkItem),
        mutex: std.Thread.Mutex,
        
        pub fn init(allocator: std.mem.Allocator) GlobalQueuePtr {
            return GlobalQueuePtr{
                .items = std.ArrayList(*WorkItem).init(allocator),
                .mutex = .{},
            };
        }
        
        pub fn deinit(self: *GlobalQueuePtr) void {
            self.items.deinit();
        }
        
        pub fn push(self: *GlobalQueuePtr, item: *WorkItem) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.append(item);
        }
        
        pub fn pop(self: *GlobalQueuePtr) ?*WorkItem {
            self.mutex.lock();
            defer self.mutex.unlock();
            return if (self.items.items.len > 0) self.items.pop() else null;
        }
        
        pub fn empty(self: *GlobalQueuePtr) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len == 0;
        }
    };
    
    pub fn initPtrQueues(self: *OptimizedWorkStealer) !void {
        self.local_queues_ptr = try self.allocator.alloc(LocalQueuePtr, self.thread_count);
        errdefer self.allocator.free(self.local_queues_ptr);
        
        for (self.local_queues_ptr, 0..) |*queue, i| {
            queue.* = try LocalQueuePtr.init(self.allocator, 256);
            errdefer {
                for (self.local_queues_ptr[0..i]) |*q| {
                    q.deinit(self.allocator);
                }
            }
        }
        
        self.global_queue_ptr = GlobalQueuePtr.init(self.allocator);
    }
    
    pub fn deinitPtrQueues(self: *OptimizedWorkStealer) void {
        if (self.local_queues_ptr.len > 0) {
            for (self.local_queues_ptr) |*queue| {
                queue.deinit(self.allocator);
            }
            self.allocator.free(self.local_queues_ptr);
        }
        self.global_queue_ptr.deinit();
    }
    
    pub fn submitWorkPtr(self: *OptimizedWorkStealer, item: *WorkItem, preferred_thread: ?usize) !void {
        if (self.local_queues_ptr.len == 0) {
            try self.initPtrQueues();
        }
        
        if (preferred_thread) |thread_id| {
            if (thread_id < self.thread_count) {
                // Try local queue first
                if (self.local_queues_ptr[thread_id].pushLocal(item)) {
                    // Mark thread as hot
                    _ = self.hot_threads.fetchOr(@as(u64, 1) << @intCast(thread_id), .release);
                    
                    // Update affinity
                    if (item.chunk_id < self.chunk_affinity.len) {
                        self.chunk_affinity[item.chunk_id] = @intCast(thread_id);
                    }
                    return;
                }
            }
        }
        
        // Fall back to global queue
        try self.global_queue_ptr.push(item);
    }
    
    pub fn getWorkPtr(self: *OptimizedWorkStealer, thread_id: usize) ?*WorkItem {
        if (self.local_queues_ptr.len == 0) return null;
        
        // 1. Check local queue first (fastest path)
        if (self.local_queues_ptr[thread_id].popLocal()) |item| {
            _ = self.local_hits.fetchAdd(1, .monotonic);
            return item;
        }
        
        // 2. Check global queue
        if (!self.global_queue_ptr.empty()) {
            if (self.global_queue_ptr.pop()) |item| {
                return item;
            }
        }
        
        // 3. Try work stealing
        return self.stealWorkPtr(thread_id);
    }
    
    fn stealWorkPtr(self: *OptimizedWorkStealer, thief_id: usize) ?*WorkItem {
        _ = self.steal_attempts.fetchAdd(1, .monotonic);
        
        const hot_mask = self.hot_threads.load(.acquire);
        if (hot_mask == 0) return null;
        
        // Prefer stealing from hot threads
        var victim_id = thief_id;
        var attempts: usize = 0;
        
        while (attempts < self.thread_count * 2) {
            victim_id = (victim_id + 1) % self.thread_count;
            if (victim_id == thief_id) continue;
            
            // Check if victim is hot
            const victim_bit = @as(u64, 1) << @intCast(victim_id);
            if ((hot_mask & victim_bit) != 0) {
                if (self.local_queues_ptr[victim_id].steal()) |item| {
                    _ = self.steal_success.fetchAdd(1, .monotonic);
                    return item;
                }
            }
            
            attempts += 1;
        }
        
        // Try any thread
        for (0..self.thread_count) |i| {
            if (i != thief_id) {
                if (self.local_queues_ptr[i].steal()) |item| {
                    _ = self.steal_success.fetchAdd(1, .monotonic);
                    return item;
                }
            }
        }
        
        return null;
    }
    
    /// Submit work with affinity hint
    pub fn submitWork(self: *OptimizedWorkStealer, item: WorkItem, preferred_thread: ?usize) !void {
        if (preferred_thread) |thread_id| {
            if (thread_id < self.thread_count) {
                // Try local queue first
                if (self.local_queues[thread_id].pushLocal(item)) {
                    // Mark thread as hot
                    _ = self.hot_threads.fetchOr(@as(u64, 1) << @intCast(thread_id), .release);
                    
                    // Update affinity
                    if (item.chunk_id < self.chunk_affinity.len) {
                        self.chunk_affinity[item.chunk_id] = @intCast(thread_id);
                    }
                    return;
                }
            }
        }
        
        // Fall back to global queue
        try self.global_queue.push(item);
    }
    
    /// Get work for a thread with optimized strategy
    pub fn getWork(self: *OptimizedWorkStealer, thread_id: usize) ?WorkItem {
        // 1. Check local queue first (fastest path)
        if (self.local_queues[thread_id].popLocal()) |item| {
            _ = self.local_hits.fetchAdd(1, .monotonic);
            return item;
        }
        
        // 2. Check global queue
        if (!self.global_queue.empty()) {
            if (self.global_queue.pop()) |item| {
                return item;
            }
        }
        
        // 3. Steal from other threads
        return self.stealWork(thread_id);
    }
    
    fn stealWork(self: *OptimizedWorkStealer, thief_id: usize) ?WorkItem {
        _ = self.steal_attempts.fetchAdd(1, .monotonic);
        
        const hot_mask = self.hot_threads.load(.acquire);
        if (hot_mask == 0) return null;
        
        // Prefer stealing from hot threads
        var victim_id = thief_id;
        var attempts: usize = 0;
        
        while (attempts < self.thread_count * 2) {
            victim_id = (victim_id + 1) % self.thread_count;
            if (victim_id == thief_id) continue;
            
            // Check if victim is hot
            const is_hot = (hot_mask & (@as(u64, 1) << @intCast(victim_id))) != 0;
            if (is_hot or attempts >= self.thread_count) {
                if (self.local_queues[victim_id].steal()) |item| {
                    _ = self.steal_success.fetchAdd(1, .monotonic);
                    
                    // Update hot threads mask if queue is now empty
                    if (self.local_queues[victim_id].size() == 0) {
                        _ = self.hot_threads.fetchAnd(~(@as(u64, 1) << @intCast(victim_id)), .release);
                    }
                    
                    return item;
                }
            }
            
            attempts += 1;
        }
        
        return null;
    }
    
    /// Process work item with optimized JSON minification
    pub fn processWork(item: *WorkItem) void {
        var output_pos: u32 = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        // Optimized processing with bulk operations
        while (i < item.input.len) {
            if (in_string) {
                // In string: bulk copy until quote or escape
                const start = i;
                while (i < item.input.len) {
                    const c = item.input[i];
                    if (escaped) {
                        escaped = false;
                        i += 1;
                    } else if (c == '\\') {
                        escaped = true;
                        i += 1;
                    } else if (c == '"') {
                        // Copy string content including closing quote
                        const len = i - start + 1;
                        @memcpy(item.output[output_pos..output_pos + len], item.input[start..i + 1]);
                        output_pos += @intCast(len);
                        in_string = false;
                        i += 1;
                        break;
                    } else {
                        i += 1;
                    }
                }
                
                // Handle end of input while in string
                if (in_string and i >= item.input.len) {
                    const len = i - start;
                    @memcpy(item.output[output_pos..output_pos + len], item.input[start..i]);
                    output_pos += @intCast(len);
                }
            } else {
                // Outside string: skip whitespace efficiently
                if (i + 8 <= item.input.len) {
                    // Process 8 bytes at once
                    const chunk = item.input[i..i + 8];
                    var j: usize = 0;
                    while (j < 8) : (j += 1) {
                        const c = chunk[j];
                        if (c == '"') {
                            item.output[output_pos] = c;
                            output_pos += 1;
                            in_string = true;
                            i += j + 1;
                            break;
                        } else if (!isWhitespace(c)) {
                            item.output[output_pos] = c;
                            output_pos += 1;
                        }
                    }
                    if (j == 8) {
                        i += 8;
                    }
                } else {
                    // Process remaining bytes
                    const c = item.input[i];
                    if (c == '"') {
                        item.output[output_pos] = c;
                        output_pos += 1;
                        in_string = true;
                    } else if (!isWhitespace(c)) {
                        item.output[output_pos] = c;
                        output_pos += 1;
                    }
                    i += 1;
                }
            }
        }
        
        item.output_size.store(output_pos, .release);
        item.completed.store(true, .release);
    }
    
    inline fn isWhitespace(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }
    
    pub fn getStats(self: *OptimizedWorkStealer) WorkStealerStats {
        const steal_rate = if (self.steal_attempts.load(.monotonic) > 0)
            @as(f64, @floatFromInt(self.steal_success.load(.monotonic))) / 
            @as(f64, @floatFromInt(self.steal_attempts.load(.monotonic)))
        else
            0.0;
            
        const local_rate = if (self.local_hits.load(.monotonic) + self.steal_success.load(.monotonic) > 0)
            @as(f64, @floatFromInt(self.local_hits.load(.monotonic))) / 
            @as(f64, @floatFromInt(self.local_hits.load(.monotonic) + self.steal_success.load(.monotonic)))
        else
            0.0;
            
        return WorkStealerStats{
            .local_hits = self.local_hits.load(.monotonic),
            .steal_success = self.steal_success.load(.monotonic),
            .steal_attempts = self.steal_attempts.load(.monotonic),
            .steal_success_rate = steal_rate,
            .local_hit_rate = local_rate,
        };
    }
    
    pub const WorkStealerStats = struct {
        local_hits: u64,
        steal_success: u64,
        steal_attempts: u64,
        steal_success_rate: f64,
        local_hit_rate: f64,
    };
};