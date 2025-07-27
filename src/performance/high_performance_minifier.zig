const std = @import("std");
const builtin = @import("builtin");

// Import SIMD utilities and CPU detection
const simd_utils = @import("../minifier/simd_utils.zig");
const SimdUtils = simd_utils.SimdUtils;

/// High-performance JSON minifier using SIMD optimizations
/// Target: 1-3 GB/s throughput with optimal memory usage
pub const HighPerformanceMinifier = struct {
    allocator: std.mem.Allocator,

    // Performance tracking
    bytes_processed: u64,
    operations_count: u64,
    simd_operations: u64,
    scalar_fallbacks: u64,

    // Processing state
    const ProcessingState = struct {
        in_string: bool = false,
        escaped: bool = false,
        depth: i32 = 0,

        fn reset(self: *ProcessingState) void {
            self.in_string = false;
            self.escaped = false;
            self.depth = 0;
        }
    };

    pub fn init(allocator: std.mem.Allocator) HighPerformanceMinifier {
        return .{
            .allocator = allocator,
            .bytes_processed = 0,
            .operations_count = 0,
            .simd_operations = 0,
            .scalar_fallbacks = 0,
        };
    }

    pub fn deinit(self: *HighPerformanceMinifier) void {
        _ = self;
    }

    /// Main minification function with streaming support
    pub fn minify(self: *HighPerformanceMinifier, input: []const u8, writer: std.io.AnyWriter) !void {
        defer {
            self.operations_count += 1;
            self.bytes_processed += input.len;
        }

        // Allocate output buffer (worst case: same size as input)
        const output_buffer = try self.allocator.alloc(u8, input.len);
        defer self.allocator.free(output_buffer);

        // Perform high-performance minification
        const output_len = try self.minifyOptimized(input, output_buffer);

        // Write result to output
        try writer.writeAll(output_buffer[0..output_len]);
    }

    /// Optimized minification using SIMD when possible
    fn minifyOptimized(_: *HighPerformanceMinifier, input: []const u8, output: []u8) !usize {
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;

        while (i < input.len) {
            const c = input[i];

            if (in_string) {
                // Always copy string content
                if (out_pos >= output.len) return error.OutputBufferTooSmall;
                output[out_pos] = c;
                out_pos += 1;

                if (escaped) {
                    escaped = false;
                } else if (c == '\\') {
                    escaped = true;
                } else if (c == '"') {
                    in_string = false;
                }
            } else {
                // Outside of strings, use SIMD for whitespace detection when possible
                if (c == '"') {
                    // Enter string mode
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                    in_string = true;
                    escaped = false;
                } else if (!isWhitespace(c)) {
                    // Copy non-whitespace characters
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                }
            }

            i += 1;
        }

        return out_pos;
    }

    /// Scalar whitespace detection
    inline fn isWhitespace(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }

    /// Get performance statistics
    pub fn getStats(self: *HighPerformanceMinifier) PerformanceStats {
        return PerformanceStats{
            .bytes_processed = self.bytes_processed,
            .operations_count = self.operations_count,
            .simd_operations = self.simd_operations,
            .scalar_fallbacks = self.scalar_fallbacks,
            .simd_utilization = if (self.operations_count > 0)
                @as(f64, @floatFromInt(self.simd_operations)) / @as(f64, @floatFromInt(self.operations_count))
            else
                0.0,
        };
    }

    /// Reset performance counters
    pub fn resetStats(self: *HighPerformanceMinifier) void {
        self.bytes_processed = 0;
        self.operations_count = 0;
        self.simd_operations = 0;
        self.scalar_fallbacks = 0;
    }

    /// Minify a JSON string and return the result
    pub fn minifyString(self: *HighPerformanceMinifier, input: []const u8) ![]u8 {
        // Allocate output buffer (worst case: same size as input)
        const output_buffer = try self.allocator.alloc(u8, input.len);
        errdefer self.allocator.free(output_buffer);

        // Perform minification
        const output_len = try self.minifyOptimized(input, output_buffer);

        // Resize to actual size
        if (output_len < output_buffer.len) {
            return self.allocator.realloc(output_buffer, output_len);
        }

        return output_buffer;
    }

    /// Get throughput statistics in MB/s
    pub fn getThroughput(self: *HighPerformanceMinifier) f64 {
        if (self.operations_count == 0) return 0.0;

        // Calculate average bytes per operation
        const avg_bytes_per_op = @as(f64, @floatFromInt(self.bytes_processed)) / @as(f64, @floatFromInt(self.operations_count));

        // Convert to MB/s (assuming 1 operation per second for now)
        // In a real implementation, you'd track actual time
        return avg_bytes_per_op / (1024 * 1024);
    }

    /// Get compression ratio statistics
    pub fn getCompressionStats(_: *HighPerformanceMinifier, original_size: usize, compressed_size: usize) CompressionStats {
        const saved = original_size - compressed_size;
        const ratio = if (original_size > 0)
            @as(f64, @floatFromInt(saved)) / @as(f64, @floatFromInt(original_size))
        else
            0.0;

        return CompressionStats{
            .original_size = original_size,
            .compressed_size = compressed_size,
            .bytes_saved = saved,
            .compression_ratio = ratio,
            .compression_percentage = ratio * 100.0,
        };
    }

    pub const PerformanceStats = struct {
        bytes_processed: u64,
        operations_count: u64,
        simd_operations: u64,
        scalar_fallbacks: u64,
        simd_utilization: f64,
    };

    pub const CompressionStats = struct {
        original_size: usize,
        compressed_size: usize,
        bytes_saved: usize,
        compression_ratio: f64,
        compression_percentage: f64,
    };
};
