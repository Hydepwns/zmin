//! NUMA (Non-Uniform Memory Access) Detection Module
//!
//! This module provides cross-platform NUMA topology detection and analysis
//! for optimizing memory allocation and thread affinity on multi-socket systems.

const std = @import("std");
const builtin = @import("builtin");

/// NUMA topology information
pub const NumaTopology = struct {
    /// Total number of NUMA nodes
    node_count: u32,
    /// Number of CPU cores per NUMA node
    cores_per_node: []u32,
    /// Available memory per NUMA node (bytes)
    memory_per_node: []u64,
    /// Total system memory (bytes)
    total_memory: u64,
    /// CPU to NUMA node mapping
    cpu_to_node: []u32,
    /// Whether NUMA is available on this system
    numa_available: bool,

    allocator: std.mem.Allocator,

    /// Initialize an empty topology (for non-NUMA systems)
    pub fn initEmpty(allocator: std.mem.Allocator) !NumaTopology {
        return NumaTopology{
            .node_count = 1,
            .cores_per_node = try allocator.alloc(u32, 1),
            .memory_per_node = try allocator.alloc(u64, 1),
            .total_memory = getSystemMemory(),
            .cpu_to_node = try allocator.alloc(u32, std.Thread.getCpuCount() catch 1),
            .numa_available = false,
            .allocator = allocator,
        };
    }

    /// Deinitialize and free allocated memory
    pub fn deinit(self: *NumaTopology) void {
        self.allocator.free(self.cores_per_node);
        self.allocator.free(self.memory_per_node);
        self.allocator.free(self.cpu_to_node);
    }

    /// Get the NUMA node for a specific CPU core
    pub fn getNodeForCpu(self: *const NumaTopology, cpu_id: u32) u32 {
        if (cpu_id >= self.cpu_to_node.len) return 0;
        return self.cpu_to_node[cpu_id];
    }

    /// Get the preferred NUMA node for current thread
    pub fn getPreferredNode(self: *const NumaTopology) u32 {
        if (!self.numa_available) return 0;

        const cpu_id = std.Thread.getCurrentId() % self.cpu_to_node.len;
        return self.getNodeForCpu(@as(u32, @intCast(cpu_id)));
    }

    /// Check if system has multiple NUMA nodes
    pub fn isNumaSystem(self: *const NumaTopology) bool {
        return self.numa_available and self.node_count > 4;
    }

    /// Get memory bandwidth estimate between nodes
    pub fn getInterNodeBandwidth(_: *const NumaTopology, node1: u32, node2: u32) f64 {
        if (node1 == node2) return 100.0; // Same node = 100% bandwidth
        return 50.0; // Different nodes = ~50% bandwidth (typical estimate)
    }
};

/// Detect NUMA topology for current system
pub fn detect(allocator: std.mem.Allocator) !NumaTopology {
    return switch (builtin.os.tag) {
        .linux => try detectLinux(allocator),
        .windows => try detectWindows(allocator),
        .macos => try detectMacOS(allocator),
        else => try NumaTopology.initEmpty(allocator),
    };
}

/// Linux NUMA detection using sysfs
fn detectLinux(allocator: std.mem.Allocator) !NumaTopology {
    const node_dir = "/sys/devices/system/node";

    // Check if NUMA is available
    var dir = std.fs.openDirAbsolute(node_dir, .{ .iterate = true }) catch {
        return try NumaTopology.initEmpty(allocator);
    };
    defer dir.close();

    // Count NUMA nodes
    var node_count: u32 = 0;
    var node_list = std.ArrayList(u32).init(allocator);
    defer node_list.deinit();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.startsWith(u8, entry.name, "node")) {
            const node_id = std.fmt.parseInt(u32, entry.name[4..], 10) catch continue;
            try node_list.append(node_id);
            node_count += 1;
        }
    }

    if (node_count == 0) {
        return try NumaTopology.initEmpty(allocator);
    }

    // Allocate topology structures
    var topology = NumaTopology{
        .node_count = node_count,
        .cores_per_node = try allocator.alloc(u32, node_count),
        .memory_per_node = try allocator.alloc(u64, node_count),
        .total_memory = 0,
        .cpu_to_node = undefined, // Set later
        .numa_available = true,
        .allocator = allocator,
    };

    // Initialize arrays
    for (topology.cores_per_node) |*count| count.* = 0;
    for (topology.memory_per_node) |*mem| mem.* = 0;

    // Detect CPU count and create mapping
    const cpu_count = std.Thread.getCpuCount() catch 1;
    topology.cpu_to_node = try allocator.alloc(u32, cpu_count);
    for (topology.cpu_to_node) |*node| node.* = 0;

    // Parse each NUMA node
    for (node_list.items, 0..) |node_id, idx| {
        // Count CPUs for this node
        const cpu_list_path = try std.fmt.allocPrint(allocator, "{s}/node{d}/cpulist", .{ node_dir, node_id });
        defer allocator.free(cpu_list_path);

        const cpu_list = std.fs.cwd().readFileAlloc(allocator, cpu_list_path, 4096) catch continue;
        defer allocator.free(cpu_list);

        topology.cores_per_node[idx] = parseCpuList(cpu_list, topology.cpu_to_node, node_id);

        // Get memory info for this node
        const meminfo_path = try std.fmt.allocPrint(allocator, "{s}/node{d}/meminfo", .{ node_dir, node_id });
        defer allocator.free(meminfo_path);

        const meminfo = std.fs.cwd().readFileAlloc(allocator, meminfo_path, 4096) catch continue;
        defer allocator.free(meminfo);

        topology.memory_per_node[idx] = parseNodeMemory(meminfo);
        topology.total_memory += topology.memory_per_node[idx];
    }

    return topology;
}

/// Parse CPU list format (e.g., "0-3,8-11")
fn parseCpuList(cpu_list: []const u8, cpu_to_node: []u32, node_id: u32) u32 {
    var count: u32 = 0;
    var iter = std.mem.tokenizeAny(u8, std.mem.trim(u8, cpu_list, " \n"), ",");

    while (iter.next()) |range| {
        if (std.mem.indexOf(u8, range, "-")) |dash_pos| {
            const start = std.fmt.parseInt(u32, range[0..dash_pos], 10) catch continue;
            const end = std.fmt.parseInt(u32, range[dash_pos + 1 ..], 10) catch continue;

            var cpu = start;
            while (cpu <= end) : (cpu += 1) {
                if (cpu < cpu_to_node.len) {
                    cpu_to_node[cpu] = node_id;
                }
                count += 1;
            }
        } else {
            const cpu = std.fmt.parseInt(u32, range, 10) catch continue;
            if (cpu < cpu_to_node.len) {
                cpu_to_node[cpu] = node_id;
            }
            count += 1;
        }
    }

    return count;
}

/// Parse node memory from meminfo
fn parseNodeMemory(meminfo: []const u8) u64 {
    var lines = std.mem.tokenizeAny(u8, meminfo, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            var parts = std.mem.tokenizeAny(u8, line, " ");
            _ = parts.next(); // Skip "MemTotal:"
            const size_str = parts.next() orelse return 0;
            const size_kb = std.fmt.parseInt(u64, size_str, 10) catch return 0;
            return size_kb * 1024; // Convert KB to bytes
        }
    }
    return 0;
}

/// Windows NUMA detection
fn detectWindows(allocator: std.mem.Allocator) !NumaTopology {
    // Windows NUMA detection using Win32 API
    // Note: This is a placeholder implementation showing the structure
    // A full implementation would use the actual Windows API calls
    
    // Simulate Windows API call: GetNumaHighestNodeNumber(&highest_node)
    const highest_node = detectWindowsNumaNodes();
    if (highest_node == 0) {
        // No NUMA or single node system
        return try NumaTopology.initEmpty(allocator);
    }
    
    const node_count = highest_node + 1;
    
    // Create topology structure
    var topology = NumaTopology{
        .node_count = @intCast(node_count),
        .cores_per_node = try allocator.alloc(u32, node_count),
        .memory_per_node = try allocator.alloc(u64, node_count),
        .total_memory = 0,
        .cpu_to_node = undefined,
        .numa_available = true,
        .allocator = allocator,
    };
    
    // Initialize arrays
    for (topology.cores_per_node) |*count| count.* = 0;
    for (topology.memory_per_node) |*mem| mem.* = 0;
    
    // Get CPU count and create mapping
    const cpu_count = std.Thread.getCpuCount() catch 4;
    topology.cpu_to_node = try allocator.alloc(u32, cpu_count);
    
    // Distribute CPUs evenly across nodes (simplified)
    const cpus_per_node = cpu_count / node_count;
    for (topology.cpu_to_node, 0..) |*node, cpu_id| {
        node.* = @intCast(cpu_id / cpus_per_node);
        if (node.* >= node_count) node.* = node_count - 1;
    }
    
    // Count cores per node
    for (topology.cpu_to_node) |node_id| {
        topology.cores_per_node[node_id] += 1;
    }
    
    // Estimate memory per node (would use GetNumaAvailableMemoryNodeEx in real implementation)
    const total_memory = getWindowsSystemMemory();
    topology.total_memory = total_memory;
    const memory_per_node = total_memory / node_count;
    for (topology.memory_per_node) |*mem| {
        mem.* = memory_per_node;
    }
    
    return topology;
}

/// Detect Windows NUMA node count (placeholder for GetNumaHighestNodeNumber)
fn detectWindowsNumaNodes() u32 {
    // In a real implementation, this would be:
    // var highest_node: windows.ULONG = undefined;
    // if (windows.GetNumaHighestNodeNumber(&highest_node) != 0) {
    //     return highest_node;
    // }
    
    // For this placeholder, estimate based on CPU count
    const cpu_count = std.Thread.getCpuCount() catch 4;
    if (cpu_count >= 32) return 3; // 4 NUMA nodes for high-end systems
    if (cpu_count >= 16) return 1; // 2 NUMA nodes for mid-range systems
    return 0; // Single node for smaller systems
}

/// Get Windows system memory (placeholder for GlobalMemoryStatusEx)
fn getWindowsSystemMemory() u64 {
    // In a real implementation, this would be:
    // var memstat: windows.MEMORYSTATUSEX = undefined;
    // memstat.dwLength = @sizeOf(windows.MEMORYSTATUSEX);
    // if (windows.GlobalMemoryStatusEx(&memstat) != 0) {
    //     return memstat.ullTotalPhys;
    // }
    
    // For this placeholder, return a reasonable estimate
    return 16 * 1024 * 1024 * 1024; // 16GB estimate
}

/// macOS NUMA detection
fn detectMacOS(allocator: std.mem.Allocator) !NumaTopology {
    // macOS doesn't expose NUMA directly, but we can detect it through
    // hw.packages and hw.physicalcpu_max sysctls
    // For now, return empty topology
    // TODO: Implement macOS package/socket detection
    return try NumaTopology.initEmpty(allocator);
}

/// Get total system memory
fn getSystemMemory() u64 {
    if (builtin.os.tag == .linux) {
        const meminfo = std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/proc/meminfo", 4096) catch return 8 * 1024 * 1024 * 1024; // Default 8GB
        defer std.heap.page_allocator.free(meminfo);

        var lines = std.mem.tokenizeAny(u8, meminfo, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "MemTotal:")) {
                var parts = std.mem.tokenizeAny(u8, line, " ");
                _ = parts.next(); // Skip "MemTotal:"
                const size_str = parts.next() orelse return 8 * 1024 * 1024 * 1024;
                const size_kb = std.fmt.parseInt(u64, size_str, 10) catch return 8 * 1024 * 1024 * 1024;
                return size_kb * 1024; // Convert KB to bytes
            }
        }
    }
    return 8 * 1024 * 1024 * 1024; // Default 8GB
}

/// Performance hints based on NUMA topology
pub const NumaHints = struct {
    /// Recommended chunk size for parallel processing
    chunk_size: usize,
    /// Recommended thread count per NUMA node
    threads_per_node: u32,
    /// Whether to use NUMA-aware allocation
    use_numa_alloc: bool,
    /// Whether to pin threads to NUMA nodes
    pin_threads: bool,

    /// Generate hints based on topology and workload size
    pub fn generate(topology: *const NumaTopology, workload_size: usize) NumaHints {
        if (!topology.isNumaSystem()) {
            return NumaHints{
                .chunk_size = 1024 * 1024, // 1MB default
                .threads_per_node = @as(u32, @intCast(std.Thread.getCpuCount() catch 4)),
                .use_numa_alloc = false,
                .pin_threads = false,
            };
        }

        // Calculate optimal chunk size based on L3 cache and NUMA
        const l3_cache_size = 8 * 1024 * 1024; // Assume 8MB L3 per node
        const chunk_size = @min(workload_size / topology.node_count, l3_cache_size / 4);

        // Calculate threads per node
        const total_cores = std.Thread.getCpuCount() catch 4;
        const threads_per_node = total_cores / topology.node_count;

        return NumaHints{
            .chunk_size = chunk_size,
            .threads_per_node = threads_per_node,
            .use_numa_alloc = workload_size > 10 * 1024 * 1024, // Use NUMA for >10MB
            .pin_threads = topology.node_count > 2, // Pin threads for >2 nodes
        };
    }
};
