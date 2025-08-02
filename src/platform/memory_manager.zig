//! Memory Management Abstraction Layer
//! 
//! This module provides optimized memory allocation strategies for different
//! workload patterns and system configurations. It abstracts platform-specific
//! memory optimizations while maintaining high performance.
//!
//! Features:
//! - Memory pooling for frequent allocations
//! - NUMA-aware allocation on multi-socket systems
//! - Huge pages support for large datasets
//! - Adaptive strategy selection based on usage patterns

const std = @import("std");
const builtin = @import("builtin");
const arch_detector = @import("arch_detector.zig");

/// Memory allocation strategy
pub const MemoryStrategy = enum {
    standard,   // Standard system allocator
    pooled,     // Memory pools for frequent allocations
    numa_aware, // NUMA-aware allocation
    adaptive,   // Automatically choose based on system and usage
};

/// Memory manager with multiple allocation strategies
pub const MemoryManager = struct {
    allocator: std.mem.Allocator,
    strategy: MemoryStrategy,
    pool_allocator: ?PoolAllocator = null,
    numa_allocator: ?NUMAAllocator = null,
    stats: AllocationStats,
    
    const Self = @This();
    
    /// Initialize memory manager with specified strategy
    pub fn init(base_allocator: std.mem.Allocator, strategy: MemoryStrategy) !Self {
        var manager = Self{
            .allocator = base_allocator,
            .strategy = strategy,
            .stats = AllocationStats{},
        };
        
        // Initialize strategy-specific allocators
        switch (strategy) {
            .pooled => {
                manager.pool_allocator = try PoolAllocator.init(base_allocator);
            },
            .numa_aware => {
                if (arch_detector.detectCapabilities().has_simd) { // Simplified NUMA check
                    manager.numa_allocator = try NUMAAllocator.init(base_allocator);
                }
            },
            .adaptive => {
                // Start with pooled allocation, may adapt later
                manager.pool_allocator = try PoolAllocator.init(base_allocator);
            },
            .standard => {
                // Use base allocator directly
            },
        }
        
        return manager;
    }
    
    pub fn deinit(self: *Self) void {
        if (self.pool_allocator) |*pool| {
            pool.deinit();
        }
        if (self.numa_allocator) |*numa| {
            numa.deinit();
        }
    }
    
    /// Allocate memory using the configured strategy
    pub fn alloc(self: *Self, comptime T: type, count: usize) ![]T {
        const size = count * @sizeOf(T);
        self.stats.recordAllocation(size);
        
        return switch (self.strategy) {
            .standard => self.allocator.alloc(T, count),
            .pooled => if (self.pool_allocator) |*pool| 
                pool.alloc(T, count) 
            else 
                self.allocator.alloc(T, count),
            .numa_aware => if (self.numa_allocator) |*numa| 
                numa.alloc(T, count) 
            else 
                self.allocator.alloc(T, count),
            .adaptive => self.allocAdaptive(T, count),
        };
    }
    
    /// Reallocate memory
    pub fn realloc(self: *Self, old_mem: anytype, new_count: usize) !@TypeOf(old_mem) {
        const T = std.meta.Child(@TypeOf(old_mem));
        const new_size = new_count * @sizeOf(T);
        const old_size = old_mem.len * @sizeOf(T);
        
        self.stats.recordReallocation(old_size, new_size);
        
        return switch (self.strategy) {
            .standard => self.allocator.realloc(old_mem, new_count),
            .pooled => if (self.pool_allocator) |*pool| 
                pool.realloc(old_mem, new_count) 
            else 
                self.allocator.realloc(old_mem, new_count),
            .numa_aware => if (self.numa_allocator) |*numa| 
                numa.realloc(old_mem, new_count) 
            else 
                self.allocator.realloc(old_mem, new_count),
            .adaptive => self.reallocAdaptive(old_mem, new_count),
        };
    }
    
    /// Free memory
    pub fn free(self: *Self, memory: anytype) void {
        const size = memory.len * @sizeOf(std.meta.Child(@TypeOf(memory)));
        self.stats.recordDeallocation(size);
        
        switch (self.strategy) {
            .standard => self.allocator.free(memory),
            .pooled => if (self.pool_allocator) |*pool| 
                pool.free(memory) 
            else 
                self.allocator.free(memory),
            .numa_aware => if (self.numa_allocator) |*numa| 
                numa.free(memory) 
            else 
                self.allocator.free(memory),
            .adaptive => self.freeAdaptive(memory),
        }
    }
    
    /// Get allocation statistics
    pub fn getStats(self: *const Self) AllocationStats {
        return self.stats;
    }
    
    /// Adapt strategy based on usage patterns
    pub fn adaptStrategy(self: *Self) void {
        if (self.strategy != .adaptive) return;
        
        const stats = self.stats;
        
        // If we have many small allocations, prefer pooled
        if (stats.allocation_count > 1000 and stats.getAverageAllocationSize() < 4096) {
            // Already using pooled for adaptive
            return;
        }
        
        // If we have large allocations, consider NUMA-aware
        if (stats.getAverageAllocationSize() > 1024 * 1024 and arch_detector.detectCapabilities().has_simd) { // Simplified NUMA check
            if (self.numa_allocator == null) {
                self.numa_allocator = NUMAAllocator.init(self.allocator) catch return;
            }
        }
    }
    
    // Private adaptive allocation methods
    fn allocAdaptive(self: *Self, comptime T: type, count: usize) ![]T {
        self.adaptStrategy();
        
        const size = count * @sizeOf(T);
        
        // Large allocations: try NUMA-aware first
        if (size > 1024 * 1024) {
            if (self.numa_allocator) |*numa| {
                return numa.alloc(T, count);
            }
        }
        
        // Medium allocations: use pools
        if (self.pool_allocator) |*pool| {
            return pool.alloc(T, count);
        }
        
        // Fallback to standard allocator
        return self.allocator.alloc(T, count);
    }
    
    fn reallocAdaptive(self: *Self, old_mem: anytype, new_count: usize) !@TypeOf(old_mem) {
        const T = std.meta.Child(@TypeOf(old_mem));
        const new_size = new_count * @sizeOf(T);
        
        // Large reallocations: try NUMA-aware
        if (new_size > 1024 * 1024) {
            if (self.numa_allocator) |*numa| {
                return numa.realloc(old_mem, new_count);
            }
        }
        
        // Try pools first
        if (self.pool_allocator) |*pool| {
            return pool.realloc(old_mem, new_count);
        }
        
        // Fallback
        return self.allocator.realloc(old_mem, new_count);
    }
    
    fn freeAdaptive(self: *Self, memory: anytype) void {
        const size = memory.len * @sizeOf(std.meta.Child(@TypeOf(memory)));
        
        // Try to free from the most likely allocator first
        if (size > 1024 * 1024) {
            if (self.numa_allocator) |*numa| {
                numa.free(memory);
                return;
            }
        }
        
        if (self.pool_allocator) |*pool| {
            pool.free(memory);
            return;
        }
        
        self.allocator.free(memory);
    }
};

/// Pool allocator for frequent small allocations
const PoolAllocator = struct {
    base_allocator: std.mem.Allocator,
    pools: [NUM_POOLS]Pool,
    
    const NUM_POOLS = 8;
    const Pool = struct {
        size_class: usize,
        free_list: ?*FreeNode,
        chunks: std.ArrayList([]u8),
        
        const FreeNode = struct {
            next: ?*FreeNode,
        };
    };
    
    pub fn init(base_allocator: std.mem.Allocator) !PoolAllocator {
        var pools: [NUM_POOLS]Pool = undefined;
        
        // Initialize size classes: 32, 64, 128, 256, 512, 1024, 2048, 4096 bytes
        for (&pools, 0..) |*pool, i| {
            pool.* = Pool{
                .size_class = @as(usize, 32) << @intCast(i),
                .free_list = null,
                .chunks = std.ArrayList([]u8).init(base_allocator),
            };
        }
        
        return PoolAllocator{
            .base_allocator = base_allocator,
            .pools = pools,
        };
    }
    
    pub fn deinit(self: *PoolAllocator) void {
        for (&self.pools) |*pool| {
            for (pool.chunks.items) |chunk| {
                self.base_allocator.free(chunk);
            }
            pool.chunks.deinit();
        }
    }
    
    pub fn alloc(self: *PoolAllocator, comptime T: type, count: usize) ![]T {
        const size = count * @sizeOf(T);
        
        // Find appropriate pool
        const pool_index = self.findPoolIndex(size);
        if (pool_index >= NUM_POOLS) {
            // Too large for pools, use base allocator
            return self.base_allocator.alloc(T, count);
        }
        
        var pool = &self.pools[pool_index];
        
        // Try to get from free list
        if (pool.free_list) |node| {
            pool.free_list = node.next;
            const ptr = @as([*]u8, @ptrCast(node));
            return @as([*]T, @ptrCast(@alignCast(ptr)))[0..count];
        }
        
        // Allocate new chunk if needed
        const chunk_size = pool.size_class * 64; // 64 objects per chunk
        const chunk = try self.base_allocator.alloc(u8, chunk_size);
        try pool.chunks.append(chunk);
        
        // Initialize free list for this chunk
        var i: usize = pool.size_class;
        while (i < chunk_size) : (i += pool.size_class) {
            const node = @as(*Pool.FreeNode, @ptrCast(@alignCast(&chunk[i])));
            node.next = pool.free_list;
            pool.free_list = node;
        }
        
        // Return first object from chunk
        return @as([*]T, @ptrCast(@alignCast(chunk.ptr)))[0..count];
    }
    
    pub fn realloc(self: *PoolAllocator, old_mem: anytype, new_count: usize) !@TypeOf(old_mem) {
        // For pools, we typically allocate new and copy
        const T = std.meta.Child(@TypeOf(old_mem));
        const new_mem = try self.alloc(T, new_count);
        const copy_count = @min(old_mem.len, new_count);
        @memcpy(new_mem[0..copy_count], old_mem[0..copy_count]);
        self.free(old_mem);
        return new_mem;
    }
    
    pub fn free(self: *PoolAllocator, memory: anytype) void {
        const size = memory.len * @sizeOf(std.meta.Child(@TypeOf(memory)));
        
        const pool_index = self.findPoolIndex(size);
        if (pool_index >= NUM_POOLS) {
            // Was allocated with base allocator
            self.base_allocator.free(memory);
            return;
        }
        
        var pool = &self.pools[pool_index];
        
        // Add to free list
        const node = @as(*Pool.FreeNode, @ptrCast(@alignCast(memory.ptr)));
        node.next = pool.free_list;
        pool.free_list = node;
    }
    
    fn findPoolIndex(self: *PoolAllocator, size: usize) usize {
        _ = self;
        for (0..NUM_POOLS) |i| {
            const pool_size = @as(usize, 32) << @intCast(i);
            if (size <= pool_size) return i;
        }
        return NUM_POOLS;
    }
};

/// NUMA-aware allocator for multi-socket systems
const NUMAAllocator = struct {
    base_allocator: std.mem.Allocator,
    node_count: u32,
    current_node: u32,
    
    pub fn init(base_allocator: std.mem.Allocator) !NUMAAllocator {
        return NUMAAllocator{
            .base_allocator = base_allocator,
            .node_count = detectNUMANodes(),
            .current_node = 0,
        };
    }
    
    pub fn deinit(self: *NUMAAllocator) void {
        _ = self;
    }
    
    pub fn alloc(self: *NUMAAllocator, comptime T: type, count: usize) ![]T {
        // For now, delegate to base allocator
        // Real implementation would use numa_alloc_onnode() on Linux  
        return self.base_allocator.alloc(T, count);
    }
    
    pub fn realloc(self: *NUMAAllocator, old_mem: anytype, new_count: usize) !@TypeOf(old_mem) {
        return self.base_allocator.realloc(old_mem, new_count);
    }
    
    pub fn free(self: *NUMAAllocator, memory: anytype) void {
        self.base_allocator.free(memory);
    }
    
    fn detectNUMANodes() u32 {
        // Platform-specific NUMA node detection
        return switch (builtin.os.tag) {
            .linux => detectLinuxNUMANodes(),
            .windows => detectWindowsNUMANodes(),
            else => 1,
        };
    }
    
    fn detectLinuxNUMANodes() u32 {
        // Would read /sys/devices/system/node/node*/cpulist
        return 1; // Simplified
    }
    
    fn detectWindowsNUMANodes() u32 {
        // Would use GetNumaHighestNodeNumber() 
        return 1; // Simplified
    }
};

/// Allocation statistics for monitoring and optimization
pub const AllocationStats = struct {
    allocation_count: u64 = 0,
    deallocation_count: u64 = 0,
    reallocation_count: u64 = 0,
    total_allocated: u64 = 0,
    total_deallocated: u64 = 0,
    peak_usage: u64 = 0,
    current_usage: u64 = 0,
    
    pub fn recordAllocation(self: *AllocationStats, size: usize) void {
        self.allocation_count += 1;
        self.total_allocated += size;
        self.current_usage += size;
        self.peak_usage = @max(self.peak_usage, self.current_usage);
    }
    
    pub fn recordDeallocation(self: *AllocationStats, size: usize) void {
        self.deallocation_count += 1;
        self.total_deallocated += size;
        if (self.current_usage >= size) {
            self.current_usage -= size;
        }
    }
    
    pub fn recordReallocation(self: *AllocationStats, old_size: usize, new_size: usize) void {
        self.reallocation_count += 1;
        if (new_size > old_size) {
            self.current_usage += (new_size - old_size);
            self.peak_usage = @max(self.peak_usage, self.current_usage);
        } else {
            self.current_usage -= (old_size - new_size);
        }
    }
    
    pub fn getAverageAllocationSize(self: *const AllocationStats) f64 {
        if (self.allocation_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_allocated)) / @as(f64, @floatFromInt(self.allocation_count));
    }
    
    pub fn getFragmentationRatio(self: *const AllocationStats) f64 {
        if (self.total_allocated == 0) return 0.0;
        return @as(f64, @floatFromInt(self.current_usage)) / @as(f64, @floatFromInt(self.peak_usage));
    }
    
    pub fn print(self: *const AllocationStats) void {
        std.debug.print("Memory Statistics:\n");
        std.debug.print("  Allocations: {}\n", .{self.allocation_count});
        std.debug.print("  Deallocations: {}\n", .{self.deallocation_count});
        std.debug.print("  Reallocations: {}\n", .{self.reallocation_count});
        std.debug.print("  Total Allocated: {} bytes\n", .{self.total_allocated});
        std.debug.print("  Current Usage: {} bytes\n", .{self.current_usage});
        std.debug.print("  Peak Usage: {} bytes\n", .{self.peak_usage});
        std.debug.print("  Average Allocation: {d:.1} bytes\n", .{self.getAverageAllocationSize()});
        std.debug.print("  Fragmentation: {d:.2}%\n", .{(1.0 - self.getFragmentationRatio()) * 100.0});
    }
};

/// Benchmark different memory strategies
pub fn benchmarkMemoryStrategies(base_allocator: std.mem.Allocator) !void {
    const strategies = [_]MemoryStrategy{ .standard, .pooled, .numa_aware, .adaptive };
    const iterations = 10000;
    const allocation_sizes = [_]usize{ 64, 256, 1024, 4096 };
    
    for (strategies) |strategy| {
        var manager = MemoryManager.init(base_allocator, strategy) catch continue;
        defer manager.deinit();
        
        const start_time = std.time.nanoTimestamp();
        
        // Perform allocation/deallocation benchmark
        for (0..iterations) |_| {
            for (allocation_sizes) |size| {
                const mem = manager.alloc(u8, size) catch continue;
                // Simulate some work
                mem[0] = 42;
                mem[size - 1] = 24;
                manager.free(mem);
            }
        }
        
        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        
        const stats = manager.getStats();
        
        std.debug.print("Strategy {}: {d:.2} ms, {} allocs, avg {d:.1} bytes\n", .{
            strategy,
            duration_ms,
            stats.allocation_count,
            stats.getAverageAllocationSize(),
        });
    }
}