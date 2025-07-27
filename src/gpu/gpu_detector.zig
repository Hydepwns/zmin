// GPU capability detection and selection
const std = @import("std");
const builtin = @import("builtin");

pub const GPUCapability = struct {
    available: bool,
    gpu_type: GPUType,
    memory_mb: u32,
    compute_units: u32,
    device_name: []const u8,

    pub const GPUType = enum {
        none,
        nvidia_cuda,
        amd_opencl,
        intel_opencl,
        generic_opencl,
    };
};

pub const GPUDetector = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GPUDetector {
        return GPUDetector{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GPUDetector) void {
        _ = self;
    }

    // Detect available GPU capabilities
    pub fn detectGPU(self: *GPUDetector) !GPUCapability {
        // Try NVIDIA CUDA first (most common for compute)
        if (try self.detectNVIDIA()) |nvidia| {
            return nvidia;
        }

        // Try OpenCL (cross-platform)
        if (try self.detectOpenCL()) |opencl| {
            return opencl;
        }

        // No GPU found
        return GPUCapability{
            .available = false,
            .gpu_type = .none,
            .memory_mb = 0,
            .compute_units = 0,
            .device_name = "None",
        };
    }

    // Check for NVIDIA GPU via nvidia-ml or nvidia-smi
    fn detectNVIDIA(self: *GPUDetector) !?GPUCapability {

        // Check if nvidia-smi exists and works
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits" },
        }) catch {
            return null; // nvidia-smi not available
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited == 0 and result.stdout.len > 0) {
            // Parse nvidia-smi output
            var lines = std.mem.splitSequence(u8, result.stdout, "\n");
            if (lines.next()) |line| {
                var parts = std.mem.splitSequence(u8, line, ", ");
                const name = parts.next() orelse "Unknown NVIDIA GPU";
                const memory_str = parts.next() orelse "0";

                const memory_mb = std.fmt.parseInt(u32, std.mem.trim(u8, memory_str, " "), 10) catch 0;

                return GPUCapability{
                    .available = true,
                    .gpu_type = .nvidia_cuda,
                    .memory_mb = memory_mb,
                    .compute_units = estimateNVIDIACores(name),
                    .device_name = try self.allocator.dupe(u8, name),
                };
            }
        }

        return null;
    }

    // Estimate CUDA cores based on GPU name (rough approximation)
    fn estimateNVIDIACores(name: []const u8) u32 {
        if (std.mem.indexOf(u8, name, "RTX 4090")) |_| return 16384;
        if (std.mem.indexOf(u8, name, "RTX 4080")) |_| return 9728;
        if (std.mem.indexOf(u8, name, "RTX 4070")) |_| return 5888;
        if (std.mem.indexOf(u8, name, "RTX 3090")) |_| return 10496;
        if (std.mem.indexOf(u8, name, "RTX 3080")) |_| return 8704;
        if (std.mem.indexOf(u8, name, "RTX 3070")) |_| return 5888;
        if (std.mem.indexOf(u8, name, "GTX 1080")) |_| return 2560;
        if (std.mem.indexOf(u8, name, "GTX 1070")) |_| return 1920;

        // Default estimate for unknown cards
        return 2048;
    }

    // Check for OpenCL capability (cross-platform)
    fn detectOpenCL(self: *GPUDetector) !?GPUCapability {

        // Try to use clinfo to detect OpenCL devices
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "clinfo", "--list" },
        }) catch {
            return null; // clinfo not available
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited == 0 and result.stdout.len > 0) {
            // Parse clinfo output for GPU devices
            var lines = std.mem.splitSequence(u8, result.stdout, "\n");
            while (lines.next()) |line| {
                if (std.mem.indexOf(u8, line, "GPU")) |_| {
                    return GPUCapability{
                        .available = true,
                        .gpu_type = .generic_opencl,
                        .memory_mb = 1024, // Default estimate
                        .compute_units = 256, // Default estimate
                        .device_name = try self.allocator.dupe(u8, "OpenCL GPU"),
                    };
                }
            }
        }

        return null;
    }

    // Check if GPU is suitable for JSON processing
    pub fn isGPUSuitableForJSON(capability: GPUCapability, file_size: usize) bool {
        if (!capability.available) return false;

        const min_memory_mb = (file_size * 3) / (1024 * 1024); // Need 3x file size for buffers
        const min_file_size = 100 * 1024 * 1024; // 100MB minimum

        return file_size >= min_file_size and capability.memory_mb >= min_memory_mb;
    }

    // Get performance estimate for GPU processing
    pub fn estimateGPUPerformance(capability: GPUCapability, file_size: usize) f64 {
        if (!capability.available) return 0.0;

        // Base estimate based on memory bandwidth and compute units
        const base_throughput: f64 = switch (capability.gpu_type) {
            .nvidia_cuda => @as(f64, @floatFromInt(capability.compute_units)) * 0.5, // MB/s per core
            .generic_opencl => @as(f64, @floatFromInt(capability.compute_units)) * 0.3,
            else => 100.0,
        };

        // Adjust for file size (larger files benefit more from GPU)
        const size_factor = @min(@as(f64, @floatFromInt(file_size)) / (100.0 * 1024.0 * 1024.0), // Scale based on 100MB
            10.0 // Cap at 10x benefit
            );

        return base_throughput * size_factor;
    }
};
