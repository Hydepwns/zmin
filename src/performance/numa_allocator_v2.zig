// Simplified NUMA-aware memory allocator for multi-socket systems
const std = @import("std");
const builtin = @import("builtin");

pub const NumaAllocator = struct {
    base_allocator: std.mem.Allocator,
    numa_available: bool,
    node_count: u32,
    cpu_count: usize,
    
    pub fn init(base_allocator: std.mem.Allocator) NumaAllocator {
        var self = NumaAllocator{
            .base_allocator = base_allocator,
            .numa_available = false,
            .node_count = 1,
            .cpu_count = std.Thread.getCpuCount() catch 1,
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
    
    // Allocate memory with NUMA hints
    pub fn allocForThread(self: *NumaAllocator, comptime T: type, n: usize, thread_id: usize) ![]T {
        _ = thread_id; // Will use for NUMA node assignment
        
        // For now, use regular allocation
        // In production, this would use mbind() or numa_alloc_onnode()
        return self.base_allocator.alloc(T, n);
    }
    
    // Free memory
    pub fn free(self: *NumaAllocator, memory: anytype) void {
        self.base_allocator.free(memory);
    }
    
    // Get suggested NUMA node for a thread
    pub fn getNodeForThread(self: *NumaAllocator, thread_id: usize) u32 {
        if (!self.numa_available or self.node_count <= 1) return 0;
        
        // Simple round-robin assignment
        const threads_per_node = (self.cpu_count + self.node_count - 1) / self.node_count;
        return @intCast(thread_id / threads_per_node % self.node_count);
    }
    
    // Get CPUs for a specific NUMA node
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
    
    // Set thread affinity to specific CPUs
    pub fn setThreadAffinity(self: *NumaAllocator, cpus: []const u32) !void {
        _ = self;
        
        if (builtin.os.tag == .linux) {
            var cpu_set = std.mem.zeroes(std.os.linux.cpu_set_t);
            
            for (cpus) |cpu| {
                const cpu_index = cpu / @bitSizeOf(usize);
                const cpu_bit = @as(usize, 1) << @intCast(cpu % @bitSizeOf(usize));
                if (cpu_index < cpu_set.len) {
                    cpu_set[cpu_index] |= cpu_bit;
                }
            }
            
            std.os.linux.sched_setaffinity(0, &cpu_set) catch {};
        }
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
    
    pub fn getInfo(self: *NumaAllocator) Info {
        return Info{
            .numa_available = self.numa_available,
            .node_count = self.node_count,
            .cpu_count = self.cpu_count,
        };
    }
    
    pub const Info = struct {
        numa_available: bool,
        node_count: u32,
        cpu_count: usize,
    };
};