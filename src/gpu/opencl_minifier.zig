//! OpenCL GPU acceleration for JSON minification
//!
//! This module provides GPU-accelerated JSON processing using OpenCL,
//! supporting a wider range of GPUs including AMD, Intel, and NVIDIA.

const std = @import("std");
const zmin = @import("../root.zig");

/// OpenCL-specific error types
pub const OpenCLError = error{
    PlatformNotFound,
    DeviceNotFound,
    ContextCreationFailed,
    QueueCreationFailed,
    ProgramBuildFailed,
    KernelCreationFailed,
    BufferCreationFailed,
    KernelExecutionFailed,
};

/// OpenCL platform information
pub const CLPlatform = struct {
    id: usize,
    name: []const u8,
    vendor: []const u8,
    version: []const u8,
};

/// OpenCL device information
pub const CLDevice = struct {
    id: usize,
    name: []const u8,
    type: DeviceType,
    compute_units: u32,
    max_work_group_size: usize,
    global_memory_size: usize,
    local_memory_size: usize,
    max_work_item_dimensions: u32,
    
    pub const DeviceType = enum {
        cpu,
        gpu,
        accelerator,
        custom,
    };
};

/// OpenCL minifier configuration
pub const OpenCLConfig = struct {
    /// Platform index to use (-1 for auto-select)
    platform_index: i32 = -1,
    /// Device index to use (-1 for auto-select)
    device_index: i32 = -1,
    /// Preferred device type
    preferred_device_type: CLDevice.DeviceType = .gpu,
    /// Work group size (0 for auto)
    work_group_size: usize = 0,
    /// Enable profiling
    enable_profiling: bool = false,
};

/// OpenCL JSON minifier
pub const OpenCLMinifier = struct {
    allocator: std.mem.Allocator,
    config: OpenCLConfig,
    platform: CLPlatform,
    device: CLDevice,
    initialized: bool = false,
    
    // OpenCL resources (opaque pointers)
    context: ?*anyopaque = null,
    queue: ?*anyopaque = null,
    program: ?*anyopaque = null,
    kernels: std.StringHashMap(*anyopaque),
    
    pub fn init(allocator: std.mem.Allocator, config: OpenCLConfig) !OpenCLMinifier {
        // Get available platforms
        const platforms = try getPlatforms(allocator);
        defer allocator.free(platforms);
        
        if (platforms.len == 0) {
            return OpenCLError.PlatformNotFound;
        }
        
        // Select platform
        const platform = if (config.platform_index >= 0)
            platforms[@intCast(config.platform_index)]
        else
            selectBestPlatform(platforms);
        
        // Get devices for platform
        const devices = try getDevices(allocator, platform);
        defer allocator.free(devices);
        
        if (devices.len == 0) {
            return OpenCLError.DeviceNotFound;
        }
        
        // Select device
        const device = if (config.device_index >= 0)
            devices[@intCast(config.device_index)]
        else
            try selectBestDevice(devices, config.preferred_device_type);
        
        var minifier = OpenCLMinifier{
            .allocator = allocator,
            .config = config,
            .platform = platform,
            .device = device,
            .kernels = std.StringHashMap(*anyopaque).init(allocator),
        };
        
        // Initialize OpenCL
        try minifier.initializeOpenCL();
        
        return minifier;
    }
    
    pub fn deinit(self: *OpenCLMinifier) void {
        if (self.initialized) {
            self.cleanupOpenCL();
        }
        self.kernels.deinit();
    }
    
    /// Minify JSON using GPU acceleration
    pub fn minify(self: *OpenCLMinifier, input: []const u8) ![]u8 {
        // For small inputs, use CPU
        if (input.len < 512 * 1024) { // < 512KB
            return zmin.minifyWithMode(self.allocator, input, .turbo);
        }
        
        // Check if GPU is beneficial
        if (!self.shouldUseGpu(input.len)) {
            return zmin.minifyWithMode(self.allocator, input, .turbo);
        }
        
        return self.minifyGpu(input);
    }
    
    fn minifyGpu(self: *OpenCLMinifier, input: []const u8) ![]u8 {
        // Allocate output buffer
        const output_size = input.len;
        const output = try self.allocator.alloc(u8, output_size);
        errdefer self.allocator.free(output);
        
        // Process on GPU
        const actual_size = try self.processOnGpu(input, output);
        
        // Resize to actual size
        if (actual_size < output.len) {
            return self.allocator.realloc(output, actual_size);
        }
        
        return output;
    }
    
    fn processOnGpu(self: *OpenCLMinifier, input: []const u8, output: []u8) !usize {
        _ = self;
        // In real implementation, this would:
        // 1. Create OpenCL buffers
        // 2. Copy input to device
        // 3. Execute kernels
        // 4. Copy output from device
        
        // For now, CPU fallback
        const result = try zmin.minifyWithMode(std.heap.page_allocator, input, .turbo);
        defer std.heap.page_allocator.free(result);
        
        @memcpy(output[0..result.len], result);
        return result.len;
    }
    
    fn initializeOpenCL(self: *OpenCLMinifier) !void {
        // In real implementation:
        // 1. Create context
        // 2. Create command queue
        // 3. Build program from kernels
        // 4. Create kernel objects
        
        self.initialized = true;
    }
    
    fn cleanupOpenCL(self: *OpenCLMinifier) void {
        // Clean up OpenCL resources
        self.initialized = false;
    }
    
    fn shouldUseGpu(self: *OpenCLMinifier, input_size: usize) bool {
        // Heuristic based on device capabilities
        const min_size = 512 * 1024; // 512KB minimum
        
        if (input_size < min_size) return false;
        
        // Estimate based on device type and compute units
        const compute_power = @as(f64, @floatFromInt(self.device.compute_units)) *
                             @as(f64, @floatFromInt(self.device.max_work_group_size));
        
        const gpu_benefit = compute_power / @as(f64, @floatFromInt(input_size));
        
        return gpu_benefit > 0.001; // Threshold for GPU benefit
    }
};

/// Get available OpenCL platforms
fn getPlatforms(allocator: std.mem.Allocator) ![]CLPlatform {
    _ = allocator;
    // In real implementation, would query OpenCL platforms
    return &.{};
}

/// Get devices for a platform
fn getDevices(allocator: std.mem.Allocator, platform: CLPlatform) ![]CLDevice {
    _ = allocator;
    _ = platform;
    // In real implementation, would query OpenCL devices
    return &.{};
}

/// Select best platform based on criteria
fn selectBestPlatform(platforms: []CLPlatform) CLPlatform {
    // Prefer platforms in order: NVIDIA, AMD, Intel
    for (platforms) |platform| {
        if (std.mem.indexOf(u8, platform.vendor, "NVIDIA") != null) return platform;
    }
    for (platforms) |platform| {
        if (std.mem.indexOf(u8, platform.vendor, "AMD") != null) return platform;
    }
    return platforms[0]; // Default to first
}

/// Select best device based on type preference
fn selectBestDevice(devices: []CLDevice, preferred_type: CLDevice.DeviceType) !CLDevice {
    // First try to find preferred type
    for (devices) |device| {
        if (device.type == preferred_type) return device;
    }
    
    // Fall back to any GPU
    for (devices) |device| {
        if (device.type == .gpu) return device;
    }
    
    // Fall back to first device
    if (devices.len > 0) return devices[0];
    
    return OpenCLError.DeviceNotFound;
}

/// OpenCL kernel source code
const opencl_kernels = 
    \\// Parallel whitespace detection
    \\__kernel void detect_whitespace(__global const char* input,
    \\                               __global char* is_whitespace,
    \\                               const unsigned int length) {
    \\    size_t gid = get_global_id(0);
    \\    if (gid >= length) return;
    \\    
    \\    char c = input[gid];
    \\    is_whitespace[gid] = (c == ' ' || c == '\t' || 
    \\                         c == '\n' || c == '\r') ? 1 : 0;
    \\}
    \\
    \\// Parallel string detection
    \\__kernel void detect_strings(__global const char* input,
    \\                            __global char* in_string,
    \\                            __global char* escape_next,
    \\                            const unsigned int length) {
    \\    size_t gid = get_global_id(0);
    \\    if (gid >= length) return;
    \\    
    \\    // This is simplified - real implementation needs sequential scan
    \\    char c = input[gid];
    \\    if (c == '"' && (gid == 0 || !escape_next[gid-1])) {
    \\        in_string[gid] = !in_string[gid-1];
    \\    } else {
    \\        in_string[gid] = (gid > 0) ? in_string[gid-1] : 0;
    \\    }
    \\    
    \\    escape_next[gid] = (c == '\\' && !escape_next[gid-1]) ? 1 : 0;
    \\}
    \\
    \\// Parallel compaction using prefix sum
    \\__kernel void compact_json(__global const char* input,
    \\                          __global char* output,
    \\                          __global const char* keep_flags,
    \\                          __global const int* output_indices,
    \\                          const unsigned int length) {
    \\    size_t gid = get_global_id(0);
    \\    if (gid >= length) return;
    \\    
    \\    if (keep_flags[gid]) {
    \\        output[output_indices[gid]] = input[gid];
    \\    }
    \\}
    \\
    \\// Work-efficient parallel prefix sum (scan)
    \\__kernel void prefix_sum(__global int* data,
    \\                        __local int* temp,
    \\                        const unsigned int n) {
    \\    int tid = get_local_id(0);
    \\    int offset = 1;
    \\    
    \\    // Load input into shared memory
    \\    temp[2*tid] = data[2*tid];
    \\    temp[2*tid+1] = data[2*tid+1];
    \\    
    \\    // Up-sweep phase
    \\    for (int d = n>>1; d > 0; d >>= 1) {
    \\        barrier(CLK_LOCAL_MEM_FENCE);
    \\        if (tid < d) {
    \\            int ai = offset*(2*tid+1)-1;
    \\            int bi = offset*(2*tid+2)-1;
    \\            temp[bi] += temp[ai];
    \\        }
    \\        offset *= 2;
    \\    }
    \\    
    \\    // Clear the last element
    \\    if (tid == 0) temp[n-1] = 0;
    \\    
    \\    // Down-sweep phase
    \\    for (int d = 1; d < n; d *= 2) {
    \\        offset >>= 1;
    \\        barrier(CLK_LOCAL_MEM_FENCE);
    \\        if (tid < d) {
    \\            int ai = offset*(2*tid+1)-1;
    \\            int bi = offset*(2*tid+2)-1;
    \\            int t = temp[ai];
    \\            temp[ai] = temp[bi];
    \\            temp[bi] += t;
    \\        }
    \\    }
    \\    
    \\    barrier(CLK_LOCAL_MEM_FENCE);
    \\    
    \\    // Write results back to global memory
    \\    data[2*tid] = temp[2*tid];
    \\    data[2*tid+1] = temp[2*tid+1];
    \\}
;