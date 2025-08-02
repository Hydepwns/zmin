//! Integrated High-Performance Memory System
//!
//! This module combines NUMA awareness, huge pages, and custom allocators
//! into a unified memory management system for maximum JSON processing performance.
//!
//! Features:
//! - NUMA-aware allocation with automatic node detection
//! - Huge pages support (2MB and 1GB) for reduced TLB misses
//! - Custom pool allocators for different object sizes
//! - Memory prefetching and optimization hints
//! - Real-time performance monitoring and adaptation

const std = @import("std");
const builtin = @import("builtin");
const NumaAllocator = @import("numa_allocator.zig").NumaAllocator;
const HugePagesAllocator = @import("hugepages_allocator.zig").HugePagesAllocator;

pub const IntegratedMemorySystem = struct {
    const Self = @This();

    base_allocator: std.mem.Allocator,
    numa_allocator: NumaAllocator,
    hugepages_allocator: HugePagesAllocator,
    pool_allocators: std.AutoHashMap(usize, PoolAllocator),
    performance_monitor: PerformanceMonitor,
    config: MemoryConfig,
    mutex: std.Thread.Mutex,

    const MemoryConfig = struct {
        enable_numa: bool = true,
        enable_hugepages: bool = true,
        enable_prefetching: bool = true,
        hugepage_threshold: usize = 64 * 1024, // 64KB
        numa_threshold: usize = 1024 * 1024, // 1MB
        pool_sizes: []const usize = &.{ 64, 128, 256, 512, 1024, 2048, 4096, 8192 },
        adaptive_optimization: bool = true,
    };

    const PoolAllocator = struct {
        size_class: usize,
        pool: std.heap.MemoryPool([]u8),
        allocations: usize,
        hit_rate: f64,
        numa_node: u32,
    };

    const PerformanceMonitor = struct {
        allocation_count: usize,
        total_allocated: usize,
        numa_hits: usize,
        hugepage_hits: usize,
        pool_hits: usize,
        avg_allocation_time: f64,
        memory_bandwidth_utilization: f64,
        tlb_miss_reduction: f64,
        
        pub fn updateAllocationMetrics(self: *PerformanceMonitor, size: usize, duration_ns: u64, allocation_type: AllocationType) void {
            self.allocation_count += 1;
            self.total_allocated += size;
            
            // Update average allocation time (exponential moving average)
            const new_time = @as(f64, @floatFromInt(duration_ns));
            if (self.avg_allocation_time == 0) {
                self.avg_allocation_time = new_time;
            } else {
                self.avg_allocation_time = 0.9 * self.avg_allocation_time + 0.1 * new_time;
            }
            
            // Update allocation type counters
            switch (allocation_type) {
                .numa => self.numa_hits += 1,
                .hugepage => self.hugepage_hits += 1,
                .pool => self.pool_hits += 1,
                .regular => {},
            }
        }
    };

    const AllocationType = enum {
        numa,
        hugepage,
        pool,
        regular,
    };

    pub fn init(base_allocator: std.mem.Allocator, config: MemoryConfig) !Self {
        var self = Self{
            .base_allocator = base_allocator,
            .numa_allocator = NumaAllocator.init(base_allocator),
            .hugepages_allocator = try HugePagesAllocator.init(base_allocator),
            .pool_allocators = std.AutoHashMap(usize, PoolAllocator).init(base_allocator),
            .performance_monitor = .{
                .allocation_count = 0,
                .total_allocated = 0,
                .numa_hits = 0,
                .hugepage_hits = 0,
                .pool_hits = 0,
                .avg_allocation_time = 0,
                .memory_bandwidth_utilization = 0,
                .tlb_miss_reduction = 0,
            },
            .config = config,
            .mutex = .{},
        };

        // Initialize pool allocators for different size classes
        if (config.enable_numa or config.enable_hugepages) {
            try self.initializePoolAllocators();
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.numa_allocator.deinit();
        self.hugepages_allocator.deinit();
        
        // Clean up pool allocators
        var iter = self.pool_allocators.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.pool.deinit();
        }
        self.pool_allocators.deinit();
    }

    /// Main allocator interface
    pub fn allocator(self: *Self) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    /// High-performance allocation with intelligent routing
    pub fn allocOptimal(self: *Self, comptime T: type, n: usize) ![]T {
        const size = n * @sizeOf(T);
        const alignment = @alignOf(T);
        const start_time = std.time.nanoTimestamp();

        const result = try self.allocateWithStrategy(T, n, size, alignment);
        
        const end_time = std.time.nanoTimestamp();
        const allocation_type = self.determineAllocationType(size);
        self.performance_monitor.updateAllocationMetrics(size, @intCast(end_time - start_time), allocation_type);

        // Apply optimizations if enabled
        if (self.config.enable_prefetching and size >= 4096) {
            self.prefetchMemory(std.mem.sliceAsBytes(result));
        }

        return result;
    }

    /// Free memory with appropriate deallocator
    pub fn freeOptimal(self: *Self, memory: anytype) void {
        const size = memory.len * @sizeOf(@TypeOf(memory[0]));
        
        // Determine which allocator was used and free accordingly
        if (size >= self.config.hugepage_threshold and self.config.enable_hugepages) {
            self.hugepages_allocator.freeHugePages(memory);
        } else if (size >= self.config.numa_threshold and self.config.enable_numa) {
            self.numa_allocator.freeMemory(memory);
        } else if (self.isPoolAllocation(memory)) {
            self.freeFromPool(memory);
        } else {
            self.base_allocator.free(memory);
        }
    }

    /// Allocate with NUMA and thread affinity optimization
    pub fn allocNuma(self: *Self, comptime T: type, n: usize, thread_id: usize) ![]T {
        if (!self.config.enable_numa) {
            return self.allocOptimal(T, n);
        }

        const size = n * @sizeOf(T);
        
        if (size >= self.config.numa_threshold) {
            return self.numa_allocator.allocForThread(T, n, thread_id);
        }

        return self.allocOptimal(T, n);
    }

    /// Allocate with huge pages for large datasets
    pub fn allocHugePages(self: *Self, comptime T: type, n: usize) ![]T {
        if (!self.config.enable_hugepages) {
            return self.allocOptimal(T, n);
        }

        return self.hugepages_allocator.allocHugePages(T, n);
    }

    /// Allocate from size-specific pool for frequent small allocations
    pub fn allocFromPool(self: *Self, comptime T: type, n: usize) ![]T {
        const size = n * @sizeOf(T);
        const size_class = self.findSizeClass(size);
        
        if (size_class == 0) {
            return self.allocOptimal(T, n);
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.pool_allocators.getPtr(size_class)) |pool| {
            if (pool.pool.create()) |bytes| {
                pool.allocations += 1;
                return @as([*]T, @ptrCast(@alignCast(bytes.ptr)))[0..n];
            } else |_| {
                // Pool exhausted, fall back to regular allocation
                return self.allocOptimal(T, n);
            }
        }

        return self.allocOptimal(T, n);
    }

    /// Optimize memory layout for cache performance
    pub fn optimizeLayout(self: *Self, memory: []u8) void {
        if (builtin.os.tag != .linux) return;

        // Use madvise hints for optimal memory layout
        const linux = std.os.linux;
        
        // Sequential access hint for large blocks
        if (memory.len >= 1024 * 1024) { // 1MB
            _ = linux.madvise(memory.ptr, memory.len, linux.MADV.SEQUENTIAL);
        }
        
        // Prefetch if configured
        if (self.config.enable_prefetching) {
            self.prefetchMemory(memory);
        }

        // NUMA optimization for large allocations
        if (self.config.enable_numa and memory.len >= self.config.numa_threshold) {
            const current_node = self.numa_allocator.getCurrentNode();
            self.hugepages_allocator.optimizeForNuma(memory, current_node) catch {};
        }
    }

    /// Prefetch memory for improved cache performance
    fn prefetchMemory(self: *Self, memory: []u8) void {
        _ = self;
        
        // Prefetch in cache line chunks (64 bytes)
        const cache_line_size = 64;
        var offset: usize = 0;
        
        while (offset < memory.len) {
            if (offset + cache_line_size <= memory.len) {
                @prefetch(memory[offset..offset + cache_line_size].ptr, .{ .rw = .read, .cache = .data });
            }
            offset += cache_line_size * 8; // Prefetch every 8th cache line
        }
    }

    /// Get comprehensive performance metrics
    pub fn getPerformanceMetrics(self: *Self) PerformanceMetrics {
        self.mutex.lock();
        defer self.mutex.unlock();

        const numa_info = self.numa_allocator.getPerformanceInfo();
        const hugepage_stats = self.hugepages_allocator.getStats();

        return PerformanceMetrics{
            .total_allocations = self.performance_monitor.allocation_count,
            .total_allocated_bytes = self.performance_monitor.total_allocated,
            .avg_allocation_time_ns = self.performance_monitor.avg_allocation_time,
            .numa_hit_rate = if (self.performance_monitor.allocation_count > 0) 
                @as(f64, @floatFromInt(self.performance_monitor.numa_hits)) / @as(f64, @floatFromInt(self.performance_monitor.allocation_count))
                else 0,
            .hugepage_hit_rate = if (self.performance_monitor.allocation_count > 0)
                @as(f64, @floatFromInt(self.performance_monitor.hugepage_hits)) / @as(f64, @floatFromInt(self.performance_monitor.allocation_count))
                else 0,
            .pool_hit_rate = if (self.performance_monitor.allocation_count > 0)
                @as(f64, @floatFromInt(self.performance_monitor.pool_hits)) / @as(f64, @floatFromInt(self.performance_monitor.allocation_count))
                else 0,
            .numa_info = numa_info,
            .hugepage_stats = hugepage_stats,
            .memory_bandwidth_utilization = self.performance_monitor.memory_bandwidth_utilization,
            .tlb_miss_reduction = hugepage_stats.tlb_miss_reduction,
        };
    }

    /// Adaptive optimization based on runtime performance
    pub fn adaptiveOptimize(self: *Self) void {
        if (!self.config.adaptive_optimization) return;

        const metrics = self.getPerformanceMetrics();
        
        // Adjust thresholds based on performance
        if (metrics.hugepage_hit_rate > 0.8 and metrics.avg_allocation_time_ns < 1000) {
            // High huge page usage with good performance - lower threshold
            self.config.hugepage_threshold = @max(32 * 1024, self.config.hugepage_threshold / 2);
        } else if (metrics.hugepage_hit_rate < 0.3) {
            // Low huge page usage - raise threshold
            self.config.hugepage_threshold = @min(1024 * 1024, self.config.hugepage_threshold * 2);
        }

        // Similar optimization for NUMA threshold
        if (metrics.numa_hit_rate > 0.7 and self.numa_allocator.numa_available) {
            self.config.numa_threshold = @max(256 * 1024, self.config.numa_threshold / 2);
        } else if (metrics.numa_hit_rate < 0.4) {
            self.config.numa_threshold = @min(4 * 1024 * 1024, self.config.numa_threshold * 2);
        }
    }

    // Private implementation methods

    fn allocateWithStrategy(self: *Self, comptime T: type, n: usize, size: usize, alignment: usize) ![]T {
        _ = alignment;

        // Strategy 1: Use pool allocator for small, frequent allocations
        const size_class = self.findSizeClass(size);
        if (size_class > 0 and size_class <= 8192) {
            if (self.allocFromPool(T, n)) |result| {
                return result;
            } else |_| {
                // Pool allocation failed, continue with other strategies
            }
        }

        // Strategy 2: Use huge pages for large allocations
        if (size >= self.config.hugepage_threshold and self.config.enable_hugepages) {
            if (self.hugepages_allocator.allocHugePages(T, n)) |result| {
                return result;
            } else |_| {
                // Huge page allocation failed, continue
            }
        }

        // Strategy 3: Use NUMA-aware allocation for medium-large allocations
        if (size >= self.config.numa_threshold and self.config.enable_numa) {
            return self.numa_allocator.allocOnNode(T, n, 0); // Use current NUMA node
        }

        // Strategy 4: Fall back to base allocator
        return self.base_allocator.alloc(T, n);
    }

    fn initializePoolAllocators(self: *Self) !void {
        for (self.config.pool_sizes) |size_class| {
            // Determine optimal NUMA node for this pool
            const numa_node = if (self.config.enable_numa) 
                self.numa_allocator.getCurrentNode() 
            else 0;

            const pool = PoolAllocator{
                .size_class = size_class,
                .pool = std.heap.MemoryPool([]u8).init(self.base_allocator),
                .allocations = 0,
                .hit_rate = 0.0,
                .numa_node = numa_node,
            };

            try self.pool_allocators.put(size_class, pool);
        }
    }

    fn findSizeClass(self: *Self, size: usize) usize {
        for (self.config.pool_sizes) |size_class| {
            if (size <= size_class) return size_class;
        }
        return 0; // No suitable size class
    }

    fn determineAllocationType(self: *Self, size: usize) AllocationType {
        if (size >= self.config.hugepage_threshold and self.config.enable_hugepages) {
            return .hugepage;
        }
        if (size >= self.config.numa_threshold and self.config.enable_numa) {
            return .numa;
        }
        if (self.findSizeClass(size) > 0) {
            return .pool;
        }
        return .regular;
    }

    fn isPoolAllocation(self: *Self, memory: anytype) bool {
        _ = self;
        _ = memory;
        // This would require tracking pool allocations
        // Simplified implementation for now
        return false;
    }

    fn freeFromPool(self: *Self, memory: anytype) void {
        _ = self;
        _ = memory;
        // Pool deallocation would be implemented here
    }

    // Allocator vtable implementation
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));
        
        const result = self.allocOptimal(u8, len) catch return null;
        return result.ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false; // Resize not supported
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = buf_align;
        _ = ret_addr;
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));
        
        self.freeOptimal(buf);
    }

    pub const PerformanceMetrics = struct {
        total_allocations: usize,
        total_allocated_bytes: usize,
        avg_allocation_time_ns: f64,
        numa_hit_rate: f64,
        hugepage_hit_rate: f64,
        pool_hit_rate: f64,
        numa_info: NumaAllocator.PerformanceInfo,
        hugepage_stats: HugePagesAllocator.HugePageStats,
        memory_bandwidth_utilization: f64,
        tlb_miss_reduction: f64,
    };
};

/// Create an optimized memory system with default configuration
pub fn createOptimizedMemorySystem(base_allocator: std.mem.Allocator) !IntegratedMemorySystem {
    const config = IntegratedMemorySystem.MemoryConfig{};
    return IntegratedMemorySystem.init(base_allocator, config);
}

/// Create a memory system optimized for JSON minification workloads
pub fn createJsonOptimizedMemorySystem(base_allocator: std.mem.Allocator) !IntegratedMemorySystem {
    const config = IntegratedMemorySystem.MemoryConfig{
        .enable_numa = true,
        .enable_hugepages = true,
        .enable_prefetching = true,
        .hugepage_threshold = 100 * 1024, // 100KB - lower for JSON processing
        .numa_threshold = 500 * 1024, // 500KB - moderate threshold
        .pool_sizes = &.{ 64, 128, 256, 512, 1024, 2048, 4096 }, // Optimize for typical JSON sizes
        .adaptive_optimization = true,
    };
    return IntegratedMemorySystem.init(base_allocator, config);
}

/// Benchmark the integrated memory system
pub fn benchmarkIntegratedSystem(base_allocator: std.mem.Allocator, iterations: usize) !struct {
    regular_time: u64,
    optimized_time: u64,
    improvement_factor: f64,
    memory_metrics: IntegratedMemorySystem.PerformanceMetrics,
} {
    // Test with various allocation sizes typical for JSON processing
    const test_sizes = [_]usize{ 256, 1024, 4096, 16384, 65536, 262144, 1048576 };
    
    // Benchmark regular allocator
    const regular_start = std.time.nanoTimestamp();
    for (0..iterations) |_| {
        for (test_sizes) |size| {
            const memory = try base_allocator.alloc(u8, size);
            // Simulate JSON processing work
            @memset(memory, 0);
            base_allocator.free(memory);
        }
    }
    const regular_end = std.time.nanoTimestamp();

    // Benchmark integrated memory system
    var integrated_system = try createJsonOptimizedMemorySystem(base_allocator);
    defer integrated_system.deinit();

    const optimized_start = std.time.nanoTimestamp();
    for (0..iterations) |_| {
        for (test_sizes) |size| {
            const memory = try integrated_system.allocOptimal(u8, size);
            integrated_system.optimizeLayout(memory);
            // Simulate JSON processing work
            @memset(memory, 0);
            integrated_system.freeOptimal(memory);
        }
    }
    const optimized_end = std.time.nanoTimestamp();

    const regular_time = @as(u64, @intCast(regular_end - regular_start));
    const optimized_time = @as(u64, @intCast(optimized_end - optimized_start));
    const improvement_factor = @as(f64, @floatFromInt(regular_time)) / @as(f64, @floatFromInt(optimized_time));

    return .{
        .regular_time = regular_time,
        .optimized_time = optimized_time,
        .improvement_factor = improvement_factor,
        .memory_metrics = integrated_system.getPerformanceMetrics(),
    };
}

test "integrated memory system" {
    var integrated_system = try createOptimizedMemorySystem(std.testing.allocator);
    defer integrated_system.deinit();

    // Test various allocation sizes
    const memory1 = try integrated_system.allocOptimal(u8, 1024);
    defer integrated_system.freeOptimal(memory1);

    const memory2 = try integrated_system.allocOptimal(u32, 10000);
    defer integrated_system.freeOptimal(memory2);

    // Get performance metrics
    const metrics = integrated_system.getPerformanceMetrics();
    try std.testing.expect(metrics.total_allocations >= 2);
}