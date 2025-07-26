// NUMA-aware memory allocator for optimized multi-socket performance
const std = @import("std");
const builtin = @import("builtin");

pub const NumaAllocator = struct {
    base_allocator: std.mem.Allocator,
    numa_available: bool,
    node_count: u32,
    preferred_node: ?u32,
    
    const linux = std.os.linux;
    const c = @cImport({
        @cInclude("sched.h");
        @cInclude("unistd.h");
        @cInclude("numaif.h");
    });
    
    // NUMA system calls (Linux-specific)
    const MPOL_DEFAULT = 0;
    const MPOL_PREFERRED = 1;
    const MPOL_BIND = 2;
    const MPOL_INTERLEAVE = 3;
    
    pub fn init(base_allocator: std.mem.Allocator) NumaAllocator {
        var self = NumaAllocator{
            .base_allocator = base_allocator,
            .numa_available = false,
            .node_count = 1,
            .preferred_node = null,
        };
        
        if (builtin.os.tag == .linux) {
            self.numa_available = checkNumaAvailable();
            if (self.numa_available) {
                self.node_count = getNumaNodeCount();
            }
        }
        
        return self;
    }
    
    pub fn deinit(self: *NumaAllocator) void {
        _ = self;
    }
    
    // Allocate memory on a specific NUMA node
    pub fn allocOnNode(self: *NumaAllocator, comptime T: type, n: usize, node: u32) ![]T {
        if (!self.numa_available or node >= self.node_count) {
            // Fallback to regular allocation
            return self.base_allocator.alloc(T, n);
        }
        
        const size = @sizeOf(T) * n;
        const alignment = @alignOf(T);
        
        if (builtin.os.tag == .linux) {
            // Use mbind to allocate on specific node
            const ptr = try self.allocateWithNode(size, alignment, node);
            return @as([*]T, @ptrCast(@alignCast(ptr)))[0..n];
        }
        
        return self.base_allocator.alloc(T, n);
    }
    
    // Allocate interleaved across all NUMA nodes
    pub fn allocInterleaved(self: *NumaAllocator, comptime T: type, n: usize) ![]T {
        if (!self.numa_available) {
            return self.base_allocator.alloc(T, n);
        }
        
        const size = @sizeOf(T) * n;
        const alignment = @alignOf(T);
        
        if (builtin.os.tag == .linux) {
            const ptr = try self.allocateInterleaved(size, alignment);
            return @as([*]T, @ptrCast(@alignCast(ptr)))[0..n];
        }
        
        return self.base_allocator.alloc(T, n);
    }
    
    // Free NUMA-allocated memory
    pub fn free(self: *NumaAllocator, memory: anytype) void {
        self.base_allocator.free(memory);
    }
    
    // Get the NUMA node for the calling thread
    pub fn getCurrentNode(self: *NumaAllocator) u32 {
        if (!self.numa_available) return 0;
        
        if (builtin.os.tag == .linux) {
            var cpu: c_int = undefined;
            var node: c_int = undefined;
            
            // Use sched_getcpu for current CPU
            const cpu_id = linux.sched_getcpu();
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
    
    // Bind thread to specific NUMA node
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
                if (cpu_index < cpu_set.mask.len) {
                    cpu_set.mask[cpu_index] |= cpu_bit;
                }
            }
            
            _ = linux.sched_setaffinity(0, &cpu_set);
        }
    }
    
    // Check if NUMA is available on the system
    fn checkNumaAvailable() bool {
        if (builtin.os.tag != .linux) return false;
        
        // Check if /sys/devices/system/node exists
        const node_dir = std.fs.openDirAbsolute("/sys/devices/system/node", .{}) catch return false;
        node_dir.close();
        
        return true;
    }
    
    // Get number of NUMA nodes
    fn getNumaNodeCount() u32 {
        if (builtin.os.tag != .linux) return 1;
        
        var count: u32 = 0;
        const node_dir = std.fs.openDirAbsolute("/sys/devices/system/node", .{ .iterate = true }) catch return 1;
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
    
    // Get CPUs for a specific NUMA node
    fn getCpusForNode(self: *NumaAllocator, node: u32) ![]u32 {
        var cpu_list = std.ArrayList(u32).init(self.base_allocator);
        defer cpu_list.deinit();
        
        if (builtin.os.tag == .linux) {
            const path = try std.fmt.allocPrint(self.base_allocator, "/sys/devices/system/node/node{}/cpulist", .{node});
            defer self.base_allocator.free(path);
            
            const file = std.fs.openFileAbsolute(path, .{}) catch {
                // If we can't read the file, return all CPUs
                const cpu_count = try std.Thread.getCpuCount();
                for (0..cpu_count) |i| {
                    try cpu_list.append(@intCast(i));
                }
                return cpu_list.toOwnedSlice();
            };
            defer file.close();
            
            const content = try file.readToEndAlloc(self.base_allocator, 4096);
            defer self.base_allocator.free(content);
            
            // Parse CPU list (format: "0-3,8-11")
            var iter = std.mem.tokenize(u8, content, ",\n");
            while (iter.next()) |range| {
                if (std.mem.indexOf(u8, range, "-")) |dash_pos| {
                    const start = try std.fmt.parseInt(u32, range[0..dash_pos], 10);
                    const end = try std.fmt.parseInt(u32, range[dash_pos + 1 ..], 10);
                    for (start..end + 1) |cpu| {
                        try cpu_list.append(@intCast(cpu));
                    }
                } else {
                    const cpu = try std.fmt.parseInt(u32, range, 10);
                    try cpu_list.append(cpu);
                }
            }
        }
        
        return cpu_list.toOwnedSlice();
    }
    
    // Platform-specific allocation with NUMA hints
    fn allocateWithNode(self: *NumaAllocator, size: usize, alignment: usize, node: u32) !*anyopaque {
        _ = alignment;
        
        if (builtin.os.tag == .linux) {
            // First allocate memory normally
            const ptr = try self.base_allocator.rawAlloc(size, @sizeOf(usize), @returnAddress());
            
            // Then use mbind to bind it to the NUMA node
            const nodemask_size = (self.node_count + 7) / 8;
            var nodemask = try self.base_allocator.alloc(u8, nodemask_size);
            defer self.base_allocator.free(nodemask);
            
            @memset(nodemask, 0);
            nodemask[node / 8] |= @as(u8, 1) << @intCast(node % 8);
            
            // mbind system call
            const ret = linux.syscall6(
                .mbind,
                @intFromPtr(ptr),
                size,
                MPOL_BIND,
                @intFromPtr(nodemask.ptr),
                nodemask_size * 8,
                0,
            );
            
            if (ret != 0) {
                // mbind failed, but memory is still allocated
                // Continue with regular memory
            }
            
            return ptr;
        }
        
        return self.base_allocator.rawAlloc(size, alignment, @returnAddress());
    }
    
    fn allocateInterleaved(self: *NumaAllocator, size: usize, alignment: usize) !*anyopaque {
        _ = alignment;
        
        if (builtin.os.tag == .linux) {
            const ptr = try self.base_allocator.rawAlloc(size, @sizeOf(usize), @returnAddress());
            
            // Use MPOL_INTERLEAVE to spread allocation across all nodes
            const nodemask_size = (self.node_count + 7) / 8;
            var nodemask = try self.base_allocator.alloc(u8, nodemask_size);
            defer self.base_allocator.free(nodemask);
            
            // Set all nodes in the mask
            @memset(nodemask, 0);
            for (0..self.node_count) |node| {
                nodemask[node / 8] |= @as(u8, 1) << @intCast(node % 8);
            }
            
            const ret = linux.syscall6(
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
    
    // Get memory policy info for diagnostics
    pub fn getMemoryPolicy(self: *NumaAllocator) MemoryPolicy {
        var policy = MemoryPolicy{
            .numa_available = self.numa_available,
            .node_count = self.node_count,
            .current_node = self.getCurrentNode(),
            .preferred_node = self.preferred_node,
        };
        
        return policy;
    }
    
    pub const MemoryPolicy = struct {
        numa_available: bool,
        node_count: u32,
        current_node: u32,
        preferred_node: ?u32,
    };
};