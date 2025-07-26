//! Memory Profiling and Tracking System
//!
//! This module provides comprehensive memory usage tracking, profiling,
//! and analysis for the zmin JSON minifier.

const std = @import("std");

/// Memory allocation event
pub const AllocationEvent = struct {
    /// Unique ID for this allocation
    id: u64,
    /// Size in bytes
    size: usize,
    /// Alignment requirement
    alignment: u8,
    /// Stack trace at allocation
    stack_trace: ?[]usize,
    /// Timestamp (microseconds since start)
    timestamp: u64,
    /// Thread ID that made allocation
    thread_id: u32,
    /// Allocation type tag
    tag: ?[]const u8,
    /// Whether this has been freed
    freed: bool = false,
    /// Timestamp when freed
    free_timestamp: u64 = 0,
};

/// Memory usage statistics
pub const MemoryStats = struct {
    /// Current memory usage
    current_usage: u64 = 0,
    /// Peak memory usage
    peak_usage: u64 = 0,
    /// Total allocations made
    total_allocations: u64 = 0,
    /// Total deallocations made
    total_deallocations: u64 = 0,
    /// Total bytes allocated
    total_allocated: u64 = 0,
    /// Total bytes freed
    total_freed: u64 = 0,
    /// Number of active allocations
    active_allocations: u64 = 0,
    /// Largest single allocation
    largest_allocation: u64 = 0,
    /// Average allocation size
    average_allocation_size: u64 = 0,
    
    /// Update statistics with new allocation
    pub fn recordAllocation(self: *MemoryStats, size: usize) void {
        self.total_allocations += 1;
        self.total_allocated += size;
        self.current_usage += size;
        self.active_allocations += 1;
        
        if (self.current_usage > self.peak_usage) {
            self.peak_usage = self.current_usage;
        }
        
        if (size > self.largest_allocation) {
            self.largest_allocation = size;
        }
        
        self.average_allocation_size = self.total_allocated / self.total_allocations;
    }
    
    /// Update statistics with deallocation
    pub fn recordDeallocation(self: *MemoryStats, size: usize) void {
        self.total_deallocations += 1;
        self.total_freed += size;
        self.current_usage -|= size; // Saturating subtraction
        self.active_allocations -|= 1;
    }
    
    /// Format statistics for display
    pub fn format(
        self: MemoryStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print(
            \\Memory Statistics:
            \\  Current Usage: {:.2}
            \\  Peak Usage: {:.2}
            \\  Active Allocations: {}
            \\  Total Allocations: {}
            \\  Average Size: {:.2}
            \\  Largest Allocation: {:.2}
        , .{
            std.fmt.fmtIntSizeBin(self.current_usage),
            std.fmt.fmtIntSizeBin(self.peak_usage),
            self.active_allocations,
            self.total_allocations,
            std.fmt.fmtIntSizeBin(self.average_allocation_size),
            std.fmt.fmtIntSizeBin(self.largest_allocation),
        });
    }
};

/// Memory profiler that tracks all allocations
pub const MemoryProfiler = struct {
    /// Base allocator to wrap
    base_allocator: std.mem.Allocator,
    /// Allocation tracking map
    allocations: std.AutoHashMap(usize, AllocationEvent),
    /// Memory statistics
    stats: MemoryStats,
    /// Start time for timestamps
    start_time: i128,
    /// Next allocation ID
    next_id: std.atomic.Value(u64),
    /// Mutex for thread safety
    mutex: std.Thread.Mutex,
    /// Configuration
    config: ProfilerConfig,
    
    /// Profiler configuration
    pub const ProfilerConfig = struct {
        /// Track stack traces
        capture_stack_traces: bool = false,
        /// Maximum stack trace depth
        max_stack_depth: usize = 10,
        /// Track allocation tags
        enable_tagging: bool = true,
        /// Report threshold (bytes)
        report_threshold: usize = 1024 * 1024, // 1MB
        /// Enable detailed tracking
        detailed_tracking: bool = true,
    };
    
    /// Initialize memory profiler
    pub fn init(base_allocator: std.mem.Allocator, config: ProfilerConfig) !*MemoryProfiler {
        const profiler = try base_allocator.create(MemoryProfiler);
        profiler.* = MemoryProfiler{
            .base_allocator = base_allocator,
            .allocations = std.AutoHashMap(usize, AllocationEvent).init(base_allocator),
            .stats = MemoryStats{},
            .start_time = std.time.nanoTimestamp(),
            .next_id = std.atomic.Value(u64).init(1),
            .mutex = std.Thread.Mutex{},
            .config = config,
        };
        return profiler;
    }
    
    /// Deinitialize memory profiler
    pub fn deinit(self: *MemoryProfiler) void {
        self.allocations.deinit();
        self.base_allocator.destroy(self);
    }
    
    /// Get allocator interface
    pub fn allocator(self: *MemoryProfiler) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }
    
    /// Allocation function
    fn alloc(
        ctx: *anyopaque,
        len: usize,
        log2_align: u8,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *MemoryProfiler = @ptrCast(@alignCast(ctx));
        
        // Allocate from base allocator
        const ptr = self.base_allocator.rawAlloc(len, log2_align, ret_addr) orelse return null;
        
        // Track allocation
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const id = self.next_id.fetchAdd(1, .monotonic);
        const timestamp = @as(u64, @intCast((std.time.nanoTimestamp() - self.start_time) / 1000));
        
        const event = AllocationEvent{
            .id = id,
            .size = len,
            .alignment = log2_align,
            .stack_trace = if (self.config.capture_stack_traces) 
                self.captureStackTrace() else null,
            .timestamp = timestamp,
            .thread_id = @intCast(std.Thread.getCurrentId()),
            .tag = null, // Set via separate API
        };
        
        if (self.config.detailed_tracking) {
            self.allocations.put(@intFromPtr(ptr), event) catch {};
        }
        
        self.stats.recordAllocation(len);
        
        // Report large allocations
        if (len >= self.config.report_threshold) {
            self.reportLargeAllocation(event) catch {};
        }
        
        return ptr;
    }
    
    /// Resize function
    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        log2_align: u8,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self: *MemoryProfiler = @ptrCast(@alignCast(ctx));
        
        const old_size = buf.len;
        const result = self.base_allocator.rawResize(buf, log2_align, new_len, ret_addr);
        
        if (result) {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            // Update tracking
            if (self.config.detailed_tracking) {
                if (self.allocations.getPtr(@intFromPtr(buf.ptr))) |event| {
                    self.stats.current_usage = self.stats.current_usage - old_size + new_len;
                    event.size = new_len;
                    
                    if (self.stats.current_usage > self.stats.peak_usage) {
                        self.stats.peak_usage = self.stats.current_usage;
                    }
                }
            } else {
                // Approximate tracking
                self.stats.current_usage = self.stats.current_usage - old_size + new_len;
            }
        }
        
        return result;
    }
    
    /// Free function
    fn free(
        ctx: *anyopaque,
        buf: []u8,
        log2_align: u8,
        ret_addr: usize,
    ) void {
        const self: *MemoryProfiler = @ptrCast(@alignCast(ctx));
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Update tracking
        if (self.config.detailed_tracking) {
            if (self.allocations.fetchRemove(@intFromPtr(buf.ptr))) |entry| {
                self.stats.recordDeallocation(entry.value.size);
            }
        } else {
            self.stats.recordDeallocation(buf.len);
        }
        
        // Free from base allocator
        self.base_allocator.rawFree(buf, log2_align, ret_addr);
    }
    
    /// Capture current stack trace
    fn captureStackTrace(self: *MemoryProfiler) ?[]usize {
        _ = self;
        // TODO: Implement stack trace capture
        return null;
    }
    
    /// Report large allocation
    fn reportLargeAllocation(self: *MemoryProfiler, event: AllocationEvent) !void {
        _ = self;
        const stderr = std.io.getStdErr().writer();
        try stderr.print(
            "[MEMORY] Large allocation: {} bytes (thread {})\n",
            .{ std.fmt.fmtIntSizeBin(event.size), event.thread_id }
        );
    }
    
    /// Tag an allocation
    pub fn tagAllocation(self: *MemoryProfiler, ptr: *anyopaque, tag: []const u8) void {
        if (!self.config.enable_tagging) return;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.allocations.getPtr(@intFromPtr(ptr))) |event| {
            event.tag = tag;
        }
    }
    
    /// Get current memory statistics
    pub fn getStats(self: *MemoryProfiler) MemoryStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.stats;
    }
    
    /// Generate memory report
    pub fn generateReport(self: *MemoryProfiler, writer: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try writer.print("Memory Profile Report\n", .{});
        try writer.print("====================\n\n", .{});
        try writer.print("{}\n\n", .{self.stats});
        
        if (self.config.detailed_tracking and self.allocations.count() > 0) {
            try writer.print("\nActive Allocations:\n", .{});
            try writer.print("-----------------\n", .{});
            
            // Sort allocations by size
            var largest_allocs = std.ArrayList(AllocationEvent).init(self.base_allocator);
            defer largest_allocs.deinit();
            
            var iter = self.allocations.iterator();
            while (iter.next()) |entry| {
                try largest_allocs.append(entry.value_ptr.*);
            }
            
            std.sort.heap(AllocationEvent, largest_allocs.items, {}, struct {
                fn lessThan(_: void, a: AllocationEvent, b: AllocationEvent) bool {
                    return a.size > b.size;
                }
            }.lessThan);
            
            // Show top 10 allocations
            const show_count = @min(10, largest_allocs.items.len);
            for (largest_allocs.items[0..show_count]) |alloc| {
                try writer.print(
                    "  - {} bytes",
                    .{std.fmt.fmtIntSizeBin(alloc.size)}
                );
                
                if (alloc.tag) |tag| {
                    try writer.print(" [{}]", .{tag});
                }
                
                try writer.print(" (thread {})\n", .{alloc.thread_id});
            }
        }
        
        // Memory usage by tag
        if (self.config.enable_tagging) {
            try self.generateTagReport(writer);
        }
    }
    
    /// Generate report grouped by tags
    fn generateTagReport(self: *MemoryProfiler, writer: anytype) !void {
        var tag_stats = std.StringHashMap(struct {
            count: u64,
            total_size: u64,
        }).init(self.base_allocator);
        defer tag_stats.deinit();
        
        var iter = self.allocations.iterator();
        while (iter.next()) |entry| {
            const tag = entry.value_ptr.tag orelse "untagged";
            const stats = try tag_stats.getOrPut(tag);
            if (!stats.found_existing) {
                stats.value_ptr.* = .{ .count = 0, .total_size = 0 };
            }
            stats.value_ptr.count += 1;
            stats.value_ptr.total_size += entry.value_ptr.size;
        }
        
        if (tag_stats.count() > 0) {
            try writer.print("\nMemory Usage by Tag:\n", .{});
            try writer.print("-------------------\n", .{});
            
            var tag_iter = tag_stats.iterator();
            while (tag_iter.next()) |tag_entry| {
                try writer.print(
                    "  {s}: {} allocations, {} total\n",
                    .{
                        tag_entry.key_ptr.*,
                        tag_entry.value_ptr.count,
                        std.fmt.fmtIntSizeBin(tag_entry.value_ptr.total_size),
                    }
                );
            }
        }
    }
    
    /// Check for memory leaks
    pub fn checkLeaks(self: *MemoryProfiler) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.allocations.count() > 0) {
            const stderr = std.io.getStdErr().writer();
            try stderr.print(
                "\n⚠️  Memory Leak Detected!\n",
                .{}
            );
            try stderr.print(
                "{} allocations ({} bytes) were not freed\n",
                .{ self.allocations.count(), std.fmt.fmtIntSizeBin(self.stats.current_usage) }
            );
            
            if (self.config.detailed_tracking) {
                try stderr.print("\nLeak Details:\n", .{});
                var iter = self.allocations.iterator();
                var shown: usize = 0;
                while (iter.next()) |entry| : (shown += 1) {
                    if (shown >= 10) {
                        try stderr.print("  ... and {} more\n", .{self.allocations.count() - shown});
                        break;
                    }
                    
                    try stderr.print(
                        "  - {} bytes",
                        .{std.fmt.fmtIntSizeBin(entry.value_ptr.size)}
                    );
                    
                    if (entry.value_ptr.tag) |tag| {
                        try stderr.print(" [{}]", .{tag});
                    }
                    
                    try stderr.print("\n", .{});
                }
            }
        }
    }
};

/// Scoped memory profiler for specific operations
pub const ScopedProfiler = struct {
    profiler: *MemoryProfiler,
    start_stats: MemoryStats,
    tag: []const u8,
    
    /// Begin profiling a scope
    pub fn begin(profiler: *MemoryProfiler, tag: []const u8) ScopedProfiler {
        return ScopedProfiler{
            .profiler = profiler,
            .start_stats = profiler.getStats(),
            .tag = tag,
        };
    }
    
    /// End profiling and get delta
    pub fn end(self: *ScopedProfiler) MemoryDelta {
        const end_stats = self.profiler.getStats();
        
        return MemoryDelta{
            .allocated = end_stats.total_allocated - self.start_stats.total_allocated,
            .freed = end_stats.total_freed - self.start_stats.total_freed,
            .peak_delta = end_stats.peak_usage - self.start_stats.peak_usage,
            .net_change = @as(i64, @intCast(end_stats.current_usage)) - 
                         @as(i64, @intCast(self.start_stats.current_usage)),
            .allocation_count = end_stats.total_allocations - self.start_stats.total_allocations,
        };
    }
};

/// Memory usage delta
pub const MemoryDelta = struct {
    allocated: u64,
    freed: u64,
    peak_delta: u64,
    net_change: i64,
    allocation_count: u64,
    
    pub fn format(
        self: MemoryDelta,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print(
            "Allocated: {}, Freed: {}, Net: {}, Peak Δ: {}",
            .{
                std.fmt.fmtIntSizeBin(self.allocated),
                std.fmt.fmtIntSizeBin(self.freed),
                if (self.net_change >= 0)
                    std.fmt.fmtIntSizeBin(@as(u64, @intCast(self.net_change)))
                else
                    std.fmt.fmtIntSizeBin(@as(u64, @intCast(-self.net_change))),
                std.fmt.fmtIntSizeBin(self.peak_delta),
            }
        );
    }
};

// Tests
test "memory profiler basic tracking" {
    const config = MemoryProfiler.ProfilerConfig{
        .detailed_tracking = true,
        .enable_tagging = true,
    };
    
    const profiler = try MemoryProfiler.init(std.testing.allocator, config);
    defer profiler.deinit();
    
    const alloc = profiler.allocator();
    
    // Test allocation
    const data = try alloc.alloc(u8, 1024);
    defer alloc.free(data);
    
    const stats = profiler.getStats();
    try std.testing.expectEqual(@as(u64, 1024), stats.current_usage);
    try std.testing.expectEqual(@as(u64, 1), stats.total_allocations);
}

test "scoped profiler" {
    const config = MemoryProfiler.ProfilerConfig{};
    const profiler = try MemoryProfiler.init(std.testing.allocator, config);
    defer profiler.deinit();
    
    const alloc = profiler.allocator();
    
    var scope = ScopedProfiler.begin(profiler, "test_scope");
    const data = try alloc.alloc(u8, 2048);
    alloc.free(data);
    
    const delta = scope.end();
    try std.testing.expectEqual(@as(u64, 2048), delta.allocated);
    try std.testing.expectEqual(@as(u64, 2048), delta.freed);
    try std.testing.expectEqual(@as(i64, 0), delta.net_change);
}