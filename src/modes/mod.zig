// Zmin Operating Modes - Different gears for different needs

const std = @import("std");

pub const ProcessingMode = enum {
    eco,
    sport,
    turbo,

    pub fn getDescription(self: ProcessingMode) []const u8 {
        return switch (self) {
            .eco => "Memory-efficient streaming (64KB constant)",
            .sport => "Balanced performance (adaptive chunking)",
            .turbo => "Maximum speed (full document in memory)",
        };
    }

    pub fn getMemoryUsage(self: ProcessingMode, file_size: usize) usize {
        return switch (self) {
            .eco => 64 * 1024, // Always 64KB
            .sport => blk: {
                // O(√n) memory scaling with 16MB cap
                const sqrt_size = std.math.sqrt(@as(f64, @floatFromInt(file_size)));
                const sqrt_bytes = @as(usize, @intFromFloat(sqrt_size));
                break :blk @min(sqrt_bytes, 16 * 1024 * 1024);
            },
            .turbo => file_size, // Full file
        };
    }
};

pub const ModeConfig = struct {
    mode: ProcessingMode = .eco,
    chunk_size: usize = 64 * 1024,
    enable_simd: bool = false,
    prefetch_distance: usize = 0,
    parallel_chunks: usize = 1,

    pub fn fromMode(mode: ProcessingMode) ModeConfig {
        return switch (mode) {
            .eco => .{
                .mode = mode,
                .chunk_size = 64 * 1024,
                .enable_simd = false,
                .prefetch_distance = 0,
                .parallel_chunks = 1,
            },
            .sport => .{
                .mode = mode,
                .chunk_size = 1024 * 1024, // 1MB chunks
                .enable_simd = true,
                .prefetch_distance = 256,
                .parallel_chunks = 4,
            },
            .turbo => .{
                .mode = mode,
                .chunk_size = std.math.maxInt(usize), // No limit
                .enable_simd = true,
                .prefetch_distance = 512,
                .parallel_chunks = std.Thread.getCpuCount() catch 8,
            },
        };
    }
};
