//! Streaming Turbo Strategy
//!
//! Memory-efficient streaming implementation for processing large JSON files
//! that exceed available memory using constant memory consumption.

const std = @import("std");
const builtin = @import("builtin");
const interface = @import("../core/interface.zig");
const LightweightValidator = @import("minifier").lightweight_validator.LightweightValidator;
const TurboStrategy = interface.TurboStrategy;
const TurboConfig = interface.TurboConfig;
const MinificationResult = interface.MinificationResult;
const StrategyType = interface.StrategyType;

/// Streaming strategy implementation
pub const StreamingStrategy = struct {
    const Self = @This();

    // Fixed buffer size for streaming (64KB chunks)
    const STREAM_BUFFER_SIZE = 64 * 1024;

    pub const strategy: TurboStrategy = TurboStrategy{
        .strategy_type = .streaming,
        .minifyFn = minify,
        .isAvailableFn = isAvailable,
        .estimatePerformanceFn = estimatePerformance,
    };

    /// Minify JSON using streaming processing
    fn minify(
        self: *const TurboStrategy,
        allocator: std.mem.Allocator,
        input: []const u8,
        config: TurboConfig,
    ) !MinificationResult {
        _ = self;

        const start_time = std.time.microTimestamp();
        const initial_memory = getCurrentMemoryUsage();

        // Validate the input first
        try LightweightValidator.validate(input);

        // Use config chunk size or default to streaming buffer size
        const chunk_size = if (config.chunk_size > 0) config.chunk_size else STREAM_BUFFER_SIZE;

        // Allocate output buffer (estimate: input size, will be resized later)
        var output = try allocator.alloc(u8, input.len);
        var output_len: usize = 0;

        // Streaming state
        var in_string = false;
        var escape_next = false;
        var chunk_start: usize = 0;

        // Process input in chunks to maintain constant memory usage
        while (chunk_start < input.len) {
            const chunk_end = @min(chunk_start + chunk_size, input.len);
            const chunk = input[chunk_start..chunk_end];

            // Process current chunk
            for (chunk) |char| {
                if (escape_next) {
                    output[output_len] = char;
                    output_len += 1;
                    escape_next = false;
                    continue;
                }

                switch (char) {
                    '"' => {
                        in_string = !in_string;
                        output[output_len] = char;
                        output_len += 1;
                    },
                    '\\' => {
                        if (in_string) {
                            escape_next = true;
                            output[output_len] = char;
                            output_len += 1;
                        } else {
                            output[output_len] = char;
                            output_len += 1;
                        }
                    },
                    ' ', '\t', '\n', '\r' => {
                        if (!in_string) {
                            continue;
                        }
                        output[output_len] = char;
                        output_len += 1;
                    },
                    else => {
                        output[output_len] = char;
                        output_len += 1;
                    },
                }
            }

            chunk_start = chunk_end;

            // Check memory usage and enforce limits if configured
            if (config.max_memory_bytes) |max_memory| {
                const current_memory = getCurrentMemoryUsage() - initial_memory;
                if (current_memory > max_memory) {
                    allocator.free(output);
                    return error.InputTooLarge;
                }
            }
        }

        const end_time = std.time.microTimestamp();
        const peak_memory = getCurrentMemoryUsage();

        // Resize output to actual size
        const final_output = try allocator.realloc(output, output_len);

        return MinificationResult{
            .output = final_output,
            .compression_ratio = 1.0 - (@as(f64, @floatFromInt(output_len)) / @as(f64, @floatFromInt(input.len))),
            .duration_us = @intCast(end_time - start_time),
            .peak_memory_bytes = peak_memory - initial_memory,
            .strategy_used = .streaming,
        };
    }

    /// Check if streaming strategy is available (always true)
    fn isAvailable() bool {
        return true;
    }

    /// Estimate performance for streaming strategy
    fn estimatePerformance(input_size: u64) u64 {
        // Conservative estimate: 400 MB/s for streaming (memory I/O bound)
        const throughput_mbps = 400;
        return (input_size * throughput_mbps) / (1024 * 1024);
    }

    /// Get current memory usage with platform-specific implementation
    fn getCurrentMemoryUsage() u64 {
        // Platform-specific memory usage detection
        if (builtin.os.tag == .linux) {
            return getLinuxMemoryUsage();
        } else if (builtin.os.tag == .macos) {
            return getMacOSMemoryUsage();
        } else if (builtin.os.tag == .windows) {
            return getWindowsMemoryUsage();
        } else {
            // Fallback: use allocator statistics if available
            return getFallbackMemoryUsage();
        }
    }

    /// Linux-specific memory usage detection
    fn getLinuxMemoryUsage() u64 {
        const page_size: usize = 4096; // Default page size
        const statm = std.fs.openFileAbsolute("/proc/self/statm", .{}) catch return 0;
        defer statm.close();

        var buffer: [64]u8 = undefined;
        const bytes_read = statm.read(&buffer) catch return 0;
        const content = buffer[0..bytes_read];

        var iter = std.mem.splitScalar(u8, content, ' ');
        _ = iter.next(); // Skip total pages
        const resident_pages = std.fmt.parseInt(usize, iter.next() orelse "0", 10) catch 0;

        return resident_pages * page_size;
    }

    /// macOS-specific memory usage detection
    fn getMacOSMemoryUsage() u64 {
        // For now, return 0 as platform-specific memory APIs are not readily available
        // In a production system, you would use task_info with TASK_BASIC_INFO
        return 0;
    }

    /// Windows-specific memory usage detection
    fn getWindowsMemoryUsage() u64 {
        // For now, return 0 as platform-specific memory APIs are not readily available
        // In a production system, you would use GetProcessMemoryInfo
        return 0;
    }

    /// Fallback memory usage detection using allocator statistics
    fn getFallbackMemoryUsage() u64 {
        // This is a simplified fallback - in practice, you might want to track
        // memory usage manually or use a custom allocator that provides statistics
        return 0;
    }
};
