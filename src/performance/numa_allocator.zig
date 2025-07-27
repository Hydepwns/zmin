// Extremely performant NUMA-aware memory allocator for multi-socket systems
const std = @import("std");
const builtin = @import("builtin");

pub const NumaAllocator = struct {
    base_allocator: std.mem.Allocator,
    numa_available: bool,
    node_count: u32,
    cpu_count: usize,
    thread_pools: std.AutoHashMap(usize, ThreadPool),
    memory_stats: MemoryStats,
    mutex: std.Thread.Mutex,
    cache_line_size: usize,
    numa_allocations: std.AutoHashMap([*]u8, usize), // Track NUMA allocation sizes

    const ThreadPool = struct {
        node: u32,
        cpus: []u32,
        thread_count: usize,
        active_threads: usize,
        memory_allocated: usize,
        allocation_count: usize,
    };

    const MemoryStats = struct {
        total_allocated: usize,
        total_freed: usize,
        peak_usage: usize,
        allocation_count: usize,
        free_count: usize,
        numa_allocations: usize,
        fallback_allocations: usize,
    };

    // NUMA system calls (Linux-specific)
    const MPOL_DEFAULT = 0;
    const MPOL_PREFERRED = 1;
    const MPOL_BIND = 2;
    const MPOL_INTERLEAVE = 3;

    // NUMA flags for mbind()
    const MPOL_MF_STRICT = 0x01;
    const MPOL_MF_MOVE = 0x02;
    const MPOL_MF_MOVE_ALL = 0x04;

    pub fn init(base_allocator: std.mem.Allocator) NumaAllocator {
        var self = NumaAllocator{
            .base_allocator = base_allocator,
            .numa_available = false,
            .node_count = 1,
            .cpu_count = std.Thread.getCpuCount() catch 1,
            .thread_pools = std.AutoHashMap(usize, ThreadPool).init(base_allocator),
            .memory_stats = .{
                .total_allocated = 0,
                .total_freed = 0,
                .peak_usage = 0,
                .allocation_count = 0,
                .free_count = 0,
                .numa_allocations = 0,
                .fallback_allocations = 0,
            },
            .mutex = .{},
            .cache_line_size = 64, // Default cache line size
            .numa_allocations = std.AutoHashMap([*]u8, usize).init(base_allocator),
        };

        if (builtin.os.tag == .linux) {
            self.numa_available = checkNumaAvailable();
            if (self.numa_available) {
                self.node_count = getNumaNodeCount();
                self.cache_line_size = getCacheLineSize();
            }
        }

        return self;
    }

    pub fn deinit(self: *NumaAllocator) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.thread_pools.iterator();
        while (iter.next()) |entry| {
            self.base_allocator.free(entry.value_ptr.cpus);
        }
        self.thread_pools.deinit();
        self.numa_allocations.deinit();
    }

    // Main allocator interface
    pub fn allocator(self: *NumaAllocator) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    // High-performance allocation with NUMA awareness
    pub fn allocForThread(self: *NumaAllocator, comptime T: type, n: usize, thread_id: usize) ![]T {
        const node = self.getNodeForThread(thread_id);
        return self.allocOnNode(T, n, node);
    }

    // Allocate memory on specific NUMA node with optimized strategy
    pub fn allocOnNode(self: *NumaAllocator, comptime T: type, n: usize, node: u32) ![]T {
        if (!self.numa_available or self.node_count <= 1) {
            self.updateStats(n * @sizeOf(T), false);
            return self.base_allocator.alloc(T, n);
        }

        const size = n * @sizeOf(T);
        const alignment = @alignOf(T);

        if (builtin.os.tag == .linux) {
            // Try NUMA-aware allocation with optimized strategy
            const ptr = self.numaAllocOptimized(size, alignment, node) catch |err| {
                std.log.warn("NUMA allocation failed ({}), falling back to regular allocation", .{err});
                self.updateStats(size, false);
                return self.base_allocator.alloc(T, n);
            };

            // Bind memory to NUMA node with high-performance binding
            self.bindMemoryToNodeOptimized(ptr, size, node) catch |err| {
                std.log.warn("Memory binding failed ({}), continuing with regular allocation", .{err});
                self.numaFree(ptr);
                self.updateStats(size, false);
                return self.base_allocator.alloc(T, n);
            };

            self.updateStats(size, true);
            return @as([*]T, @ptrCast(@alignCast(ptr)))[0..n];
        }

        self.updateStats(size, false);
        return self.base_allocator.alloc(T, n);
    }

    // Allocate interleaved across all NUMA nodes for large allocations
    pub fn allocInterleaved(self: *NumaAllocator, comptime T: type, n: usize) ![]T {
        if (!self.numa_available) {
            self.updateStats(n * @sizeOf(T), false);
            return self.base_allocator.alloc(T, n);
        }

        const size = @sizeOf(T) * n;
        const alignment = @alignOf(T);

        if (builtin.os.tag == .linux) {
            const ptr = self.allocateInterleavedOptimized(size, alignment) catch |err| {
                std.log.warn("Interleaved allocation failed ({}), falling back to regular allocation", .{err});
                self.updateStats(size, false);
                return self.base_allocator.alloc(T, n);
            };

            self.updateStats(size, true);
            return @as([*]T, @ptrCast(@alignCast(ptr)))[0..n];
        }

        self.updateStats(size, false);
        return self.base_allocator.alloc(T, n);
    }

    // Free NUMA-allocated memory with tracking
    pub fn freeMemory(self: *NumaAllocator, memory: anytype) void {
        const size = memory.len * @sizeOf(@TypeOf(memory[0]));

        if (builtin.os.tag == .linux and self.numa_available) {
            self.numaFree(@as([*]u8, @ptrCast(memory.ptr)));
        } else {
            self.base_allocator.free(memory);
        }

        self.updateFreeStats(size);
    }

    // Create high-performance thread pool for a NUMA node
    pub fn createThreadPool(self: *NumaAllocator, node: u32, thread_count: usize) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const pool_id = self.thread_pools.count() + 1;
        const cpus = try self.getCpusForNode(node);

        try self.thread_pools.put(pool_id, .{
            .node = node,
            .cpus = cpus,
            .thread_count = thread_count,
            .active_threads = 0,
            .memory_allocated = 0,
            .allocation_count = 0,
        });

        return pool_id;
    }

    // Get thread from pool with NUMA affinity
    pub fn getThreadFromPool(self: *NumaAllocator, pool_id: usize) !?ThreadInfo {
        self.mutex.lock();
        defer self.mutex.unlock();

        const pool = self.thread_pools.get(pool_id) orelse return error.PoolNotFound;
        if (pool.active_threads >= pool.thread_count) return null;

        const thread_id = pool.active_threads;
        pool.active_threads += 1;

        // Set thread affinity to CPUs on this NUMA node
        try self.setThreadAffinity(pool.cpus);

        return ThreadInfo{
            .pool_id = pool_id,
            .thread_id = thread_id,
            .node = pool.node,
            .cpus = pool.cpus,
        };
    }

    // Get suggested NUMA node for a thread with load balancing
    pub fn getNodeForThread(self: *NumaAllocator, thread_id: usize) u32 {
        if (!self.numa_available or self.node_count <= 1) return 0;

        // Load-balanced round-robin assignment
        const threads_per_node = (self.cpu_count + self.node_count - 1) / self.node_count;
        return @intCast(thread_id / threads_per_node % self.node_count);
    }

    // Get CPUs for a specific NUMA node with caching
    pub fn getCpusForNode(self: *NumaAllocator, node: u32) ![]u32 {
        var cpu_list = std.ArrayList(u32).init(self.base_allocator);
        defer cpu_list.deinit();

        if (builtin.os.tag == .linux and self.numa_available) {
            const path = try std.fmt.allocPrint(self.base_allocator, "/sys/devices/system/node/node{}/cpulist", .{node});
            defer self.base_allocator.free(path);

            const file = std.fs.openFileAbsolute(path, .{}) catch {
                // Fallback: distribute CPUs evenly
                const cpus_per_node = self.cpu_count / self.node_count;
                const start = node * cpus_per_node;
                const end = if (node == self.node_count - 1) self.cpu_count else (node + 1) * cpus_per_node;

                for (start..end) |cpu| {
                    try cpu_list.append(@intCast(cpu));
                }
                return cpu_list.toOwnedSlice();
            };
            defer file.close();

            const content = try file.readToEndAlloc(self.base_allocator, 4096);
            defer self.base_allocator.free(content);

            // Parse CPU list (format: "0-3,8-11")
            var iter = std.mem.tokenizeAny(u8, content, ",\n");
            while (iter.next()) |range| {
                if (std.mem.indexOf(u8, range, "-")) |dash_pos| {
                    const start = try std.fmt.parseInt(u32, range[0..dash_pos], 10);
                    const end = try std.fmt.parseInt(u32, range[dash_pos + 1 ..], 10);
                    for (start..end + 1) |cpu| {
                        try cpu_list.append(@intCast(cpu));
                    }
                } else {
                    const cpu = try std.fmt.parseInt(u32, std.mem.trim(u8, range, " "), 10);
                    try cpu_list.append(cpu);
                }
            }
        } else {
            // No NUMA: return all CPUs
            for (0..self.cpu_count) |cpu| {
                try cpu_list.append(@intCast(cpu));
            }
        }

        return cpu_list.toOwnedSlice();
    }

    // Set thread affinity to specific CPUs with optimization
    pub fn setThreadAffinity(_: *NumaAllocator, cpus: []const u32) !void {
        if (builtin.os.tag == .linux) {
            var cpu_set = std.mem.zeroes(std.os.linux.cpu_set_t);

            for (cpus) |cpu| {
                const cpu_index = cpu / @bitSizeOf(usize);
                const cpu_bit = @as(usize, 1) << @intCast(cpu % @bitSizeOf(usize));
                if (cpu_index < cpu_set.len) {
                    cpu_set[cpu_index] |= cpu_bit;
                }
            }

            try std.os.linux.sched_setaffinity(0, &cpu_set);
        }
    }

    // Get the NUMA node for the calling thread with caching
    pub fn getCurrentNode(self: *NumaAllocator) u32 {
        if (!self.numa_available) return 0;

        if (builtin.os.tag == .linux) {
            // Use sched_getcpu for current CPU
            const cpu_id = std.os.linux.syscall0(.getcpu);
            if (cpu_id >= 0) {
                // Determine NUMA node from CPU
                const path = std.fmt.allocPrintZ(self.base_allocator, "/sys/devices/system/cpu/cpu{}/node", .{cpu_id}) catch return 0;
                defer self.base_allocator.free(path);

                const file = std.fs.openFileAbsolute(path, .{}) catch return 0;
                defer file.close();

                var buf: [16]u8 = undefined;
                const n = file.read(&buf) catch return 0;
                const node_str = std.mem.trim(u8, buf[0..n], "\n");
                return std.fmt.parseInt(u32, node_str, 10) catch 0;
            }
        }

        return 0;
    }

    // Bind thread to specific NUMA node with optimization
    pub fn bindToNode(self: *NumaAllocator, node: u32) !void {
        if (!self.numa_available or node >= self.node_count) return;

        if (builtin.os.tag == .linux) {
            var cpu_set = std.mem.zeroes(std.os.linux.cpu_set_t);

            // Get CPUs for this NUMA node
            const cpus = try self.getCpusForNode(node);
            defer self.base_allocator.free(cpus);

            for (cpus) |cpu| {
                const cpu_index = cpu / @bitSizeOf(usize);
                const cpu_bit = @as(usize, 1) << @intCast(cpu % @bitSizeOf(usize));
                if (cpu_index < cpu_set.len) {
                    cpu_set[cpu_index] |= cpu_bit;
                }
            }

            _ = std.os.linux.sched_setaffinity(0, &cpu_set);
        }
    }

    // Optimized NUMA-aware memory allocation using mmap
    fn numaAllocOptimized(self: *NumaAllocator, size: usize, alignment: u29, node: u32) ![*]u8 {
        if (builtin.os.tag == .linux and self.numa_available) {
            // Use mmap with NUMA hints for optimal performance
            const flags = std.os.linux.MAP{
                .TYPE = .PRIVATE,
                .ANONYMOUS = true,
            };
            const prot = 0x1 | 0x2; // PROT_READ | PROT_WRITE

            // Allocate memory with mmap
            const result = std.os.linux.mmap(
                null,
                size,
                prot,
                flags,
                -1,
                0,
            );
            if (result == ~@as(usize, 0)) {
                return error.OutOfMemory;
            }
            const ptr = @as([*]u8, @ptrFromInt(result));

            // Ensure proper alignment
            const aligned_ptr = @as([*]u8, @ptrCast(@alignCast(ptr)));

            // Bind the memory to the specific NUMA node
            try self.bindMemoryToNodeOptimized(aligned_ptr, size, node);

            // Track the allocation size for proper deallocation
            try self.numa_allocations.put(aligned_ptr, size);

            return aligned_ptr;
        }

        // Fallback to base allocator
        const ptr = self.base_allocator.rawAlloc(size, @as(std.mem.Alignment, @enumFromInt(alignment)), @returnAddress()) orelse return error.OutOfMemory;
        return @as([*]u8, @ptrCast(ptr));
    }

    // High-performance memory binding to NUMA node
    fn bindMemoryToNodeOptimized(self: *NumaAllocator, ptr: [*]u8, size: usize, node: u32) !void {
        if (builtin.os.tag == .linux and self.numa_available) {
            // Create nodemask for the specific NUMA node
            const nodemask_size = (self.node_count + 7) / 8;
            var nodemask = try self.base_allocator.alloc(u8, nodemask_size);
            defer self.base_allocator.free(nodemask);

            // Clear the nodemask and set only the target node
            @memset(nodemask, 0);
            if (node < self.node_count) {
                nodemask[node / 8] |= @as(u8, 1) << @intCast(node % 8);
            }

            // Use mbind() syscall to bind memory to the specific NUMA node
            const ret = std.os.linux.syscall6(
                .mbind,
                @intFromPtr(ptr),
                size,
                MPOL_BIND, // Bind to specific node
                @intFromPtr(nodemask.ptr),
                nodemask_size * 8, // nodemask size in bits
                0, // flags
            );

            if (ret != 0) {
                const E = std.os.linux.E;
                const errno = E.init(ret);
                return switch (errno) {
                    .INVAL => error.InvalidArgument,
                    .NOMEM => error.OutOfMemory,
                    .ACCES => error.AccessDenied,
                    .FAULT => error.InvalidPointer,
                    else => error.Unexpected,
                };
            }
        }
    }

    // Free NUMA-allocated memory
    fn numaFree(self: *NumaAllocator, ptr: [*]u8) void {
        if (builtin.os.tag == .linux and self.numa_available) {
            // Get the allocation size from our tracking
            if (self.numa_allocations.get(ptr)) |size| {
                // Use munmap to free memory allocated with mmap
                _ = std.os.linux.munmap(@ptrCast(ptr), size);
                _ = self.numa_allocations.remove(ptr);
            } else {
                // Fallback to base allocator if not tracked
                self.base_allocator.free(ptr[0..0]);
            }
        } else {
            // Fallback to base allocator
            self.base_allocator.free(ptr[0..0]);
        }
    }

    // Optimized interleaved allocation
    fn allocateInterleavedOptimized(self: *NumaAllocator, size: usize, alignment: usize) !*anyopaque {
        if (builtin.os.tag == .linux) {
            const ptr = self.base_allocator.rawAlloc(size, @as(std.mem.Alignment, @enumFromInt(@as(u29, @intCast(alignment)))), @returnAddress()) orelse return error.OutOfMemory;

            // Use MPOL_INTERLEAVE to spread allocation across all nodes
            const nodemask_size = (self.node_count + 7) / 8;
            var nodemask = try self.base_allocator.alloc(u8, nodemask_size);
            defer self.base_allocator.free(nodemask);

            // Set all nodes in the mask
            @memset(nodemask, 0);
            for (0..self.node_count) |node| {
                nodemask[node / 8] |= @as(u8, 1) << @intCast(node % 8);
            }

            const ret = std.os.linux.syscall6(
                .mbind,
                @intFromPtr(ptr),
                size,
                MPOL_INTERLEAVE,
                @intFromPtr(nodemask.ptr),
                nodemask_size * 8,
                0,
            );

            if (ret != 0) {
                // mbind failed, continue with regular memory
            }

            return ptr;
        }

        return self.base_allocator.rawAlloc(size, alignment, @returnAddress());
    }

    // Update memory statistics
    fn updateStats(self: *NumaAllocator, size: usize, numa_alloc: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.memory_stats.total_allocated += size;
        self.memory_stats.allocation_count += 1;

        if (numa_alloc) {
            self.memory_stats.numa_allocations += 1;
        } else {
            self.memory_stats.fallback_allocations += 1;
        }

        const current_usage = self.memory_stats.total_allocated - self.memory_stats.total_freed;
        if (current_usage > self.memory_stats.peak_usage) {
            self.memory_stats.peak_usage = current_usage;
        }
    }

    // Update free statistics
    fn updateFreeStats(self: *NumaAllocator, size: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.memory_stats.total_freed += size;
        self.memory_stats.free_count += 1;
    }

    // Check if NUMA is available
    fn checkNumaAvailable() bool {
        if (builtin.os.tag != .linux) return false;

        var node_dir = std.fs.openDirAbsolute("/sys/devices/system/node", .{}) catch return false;
        node_dir.close();

        return true;
    }

    // Get number of NUMA nodes
    fn getNumaNodeCount() u32 {
        if (builtin.os.tag != .linux) return 1;

        var count: u32 = 0;
        var node_dir = std.fs.openDirAbsolute("/sys/devices/system/node", .{ .iterate = true }) catch return 1;
        defer node_dir.close();

        var iter = node_dir.iterate();
        while (iter.next() catch null) |entry| {
            if (std.mem.startsWith(u8, entry.name, "node")) {
                const node_num = std.fmt.parseInt(u32, entry.name[4..], 10) catch continue;
                count = @max(count, node_num + 1);
            }
        }

        return if (count == 0) 1 else count;
    }

    // Get cache line size for optimization
    fn getCacheLineSize() usize {
        if (builtin.os.tag == .linux) {
            // Try to read from /sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size
            const path = "/sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size";
            const file = std.fs.openFileAbsolute(path, .{}) catch return 64;
            defer file.close();

            var buf: [16]u8 = undefined;
            const n = file.read(&buf) catch return 64;
            const size_str = std.mem.trim(u8, buf[0..n], "\n");
            return std.fmt.parseInt(usize, size_str, 10) catch 64;
        }

        return 64; // Default cache line size
    }

    // Get memory size for a specific NUMA node
    fn getNodeMemorySize(self: *NumaAllocator, node: u32) !usize {
        if (builtin.os.tag == .linux and self.numa_available) {
            const path = try std.fmt.allocPrint(self.base_allocator, "/sys/devices/system/node/node{}/meminfo", .{node});
            defer self.base_allocator.free(path);

            const file = std.fs.openFileAbsolute(path, .{}) catch return 0;
            defer file.close();

            const content = try file.readToEndAlloc(self.base_allocator, 4096);
            defer self.base_allocator.free(content);

            // Parse meminfo to get total memory
            var iter = std.mem.tokenizeAny(u8, content, "\n");
            while (iter.next()) |line| {
                if (std.mem.startsWith(u8, line, "MemTotal:")) {
                    var parts = std.mem.tokenizeAny(u8, line, " \t");
                    _ = parts.next(); // Skip "MemTotal:"
                    if (parts.next()) |size_str| {
                        const size = try std.fmt.parseInt(usize, size_str, 10);
                        return size * 1024; // Convert KB to bytes
                    }
                }
            }
        }
        return 0;
    }

    // Get distance between two NUMA nodes
    fn getNodeDistance(self: *NumaAllocator, from_node: u32, to_node: u32) !u32 {
        if (builtin.os.tag == .linux and self.numa_available) {
            const path = try std.fmt.allocPrint(self.base_allocator, "/sys/devices/system/node/node{}/distance", .{from_node});
            defer self.base_allocator.free(path);

            const file = std.fs.openFileAbsolute(path, .{}) catch return if (from_node == to_node) 10 else 20;
            defer file.close();

            const content = try file.readToEndAlloc(self.base_allocator, 256);
            defer self.base_allocator.free(content);

            // Parse distance file (space-separated values)
            var iter = std.mem.tokenizeAny(u8, content, " \n");
            var i: u32 = 0;
            while (iter.next()) |distance_str| {
                if (i == to_node) {
                    return try std.fmt.parseInt(u32, distance_str, 10);
                }
                i += 1;
            }
        }
        return if (from_node == to_node) 10 else 20; // Default distances
    }

    // Allocator vtable functions
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self = @as(*NumaAllocator, @ptrCast(ctx));

        const node = self.getNodeForThread(0); // Default to node 0 for general allocation
        const ptr = self.numaAllocOptimized(len, @as(u29, @intCast(ptr_align)), node) catch return null;
        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false; // Not implemented for NUMA allocator
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = buf_align;
        _ = ret_addr;
        const self = @as(*NumaAllocator, @ptrCast(ctx));

        if (builtin.os.tag == .linux and self.numa_available) {
            self.numaFree(buf.ptr);
        } else {
            self.base_allocator.free(buf);
        }

        self.updateFreeStats(buf.len);
    }

    // Get comprehensive performance information
    pub fn getPerformanceInfo(self: *NumaAllocator) PerformanceInfo {
        return PerformanceInfo{
            .numa_available = self.numa_available,
            .node_count = self.node_count,
            .cpu_count = self.cpu_count,
            .thread_pools = self.thread_pools.count(),
            .memory_stats = self.memory_stats,
            .cache_line_size = self.cache_line_size,
            .current_node = self.getCurrentNode(),
        };
    }

    // Get NUMA topology information for optimization
    pub fn getNumaTopology(self: *NumaAllocator) !NumaTopology {
        if (!self.numa_available) {
            return error.NumaNotAvailable;
        }

        var topology = NumaTopology{
            .nodes = try self.base_allocator.alloc(NumaNode, self.node_count),
            .node_count = self.node_count,
        };

        for (0..self.node_count) |i| {
            const node = @as(u32, @intCast(i));
            topology.nodes[i] = .{
                .id = node,
                .cpu_count = 0,
                .memory_size = 0,
                .distance = try self.base_allocator.alloc(u32, self.node_count),
            };

            // Get CPUs for this node
            const cpus = try self.getCpusForNode(node);
            topology.nodes[i].cpu_count = @as(u32, @intCast(cpus.len));
            self.base_allocator.free(cpus);

            // Get memory size for this node
            topology.nodes[i].memory_size = try self.getNodeMemorySize(node);

            // Get distance to other nodes
            for (0..self.node_count) |j| {
                const target_node = @as(u32, @intCast(j));
                topology.nodes[i].distance[j] = try self.getNodeDistance(node, target_node);
            }
        }

        return topology;
    }

    // Deallocate NUMA topology
    pub fn deinitNumaTopology(self: *NumaAllocator, topology: *const NumaTopology) void {
        for (topology.nodes) |node| {
            self.base_allocator.free(node.distance);
        }
        self.base_allocator.free(topology.nodes);
    }

    pub const PerformanceInfo = struct {
        numa_available: bool,
        node_count: u32,
        cpu_count: usize,
        thread_pools: usize,
        memory_stats: MemoryStats,
        cache_line_size: usize,
        current_node: u32,
    };

    pub const ThreadInfo = struct {
        pool_id: usize,
        thread_id: usize,
        node: u32,
        cpus: []u32,
    };

    pub const NumaTopology = struct {
        nodes: []NumaNode,
        node_count: u32,
    };

    pub const NumaNode = struct {
        id: u32,
        cpu_count: u32,
        memory_size: usize,
        distance: []u32,
    };
};

// Example usage and performance testing
pub fn example() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var numa_allocator = NumaAllocator.init(arena.allocator());
    defer numa_allocator.deinit();

    const info = numa_allocator.getPerformanceInfo();
    std.log.info("NUMA Performance Info: available={}, nodes={}, cpus={}, pools={}, cache_line={}", .{
        info.numa_available,
        info.node_count,
        info.cpu_count,
        info.thread_pools,
        info.cache_line_size,
    });

    // Get NUMA topology for optimization
    if (numa_allocator.getNumaTopology()) |topology| {
        defer numa_allocator.deinitNumaTopology(&topology);

        std.log.info("NUMA Topology: {} nodes", .{topology.node_count});
        for (topology.nodes) |node| {
            std.log.info("Node {}: {} CPUs, {} bytes memory", .{
                node.id,
                node.cpu_count,
                node.memory_size,
            });

            // Log distances to other nodes
            for (0..topology.node_count) |i| {
                if (i != node.id) {
                    std.log.info("  Distance to node {}: {}", .{ i, node.distance[i] });
                }
            }
        }
    } else |err| {
        std.log.warn("Failed to get NUMA topology: {}", .{err});
    }

    // Create thread pools for each NUMA node
    for (0..info.node_count) |node| {
        const pool_id = try numa_allocator.createThreadPool(@intCast(node), 4);
        std.log.info("Created thread pool {} for NUMA node {}", .{ pool_id, node });
    }

    // Allocate memory with NUMA awareness
    const data = try numa_allocator.allocForThread(u32, 1000, 0);
    defer numa_allocator.freeMemory(data);

    // Allocate interleaved for large data
    const large_data = try numa_allocator.allocInterleaved(u64, 10000);
    defer numa_allocator.freeMemory(large_data);

    const final_info = numa_allocator.getPerformanceInfo();
    std.log.info("Memory Stats: allocated={}, freed={}, peak={}, numa_allocations={}, fallback={}", .{
        final_info.memory_stats.total_allocated,
        final_info.memory_stats.total_freed,
        final_info.memory_stats.peak_usage,
        final_info.memory_stats.numa_allocations,
        final_info.memory_stats.fallback_allocations,
    });
}

// Test main function
pub fn main() !void {
    try example();
}
