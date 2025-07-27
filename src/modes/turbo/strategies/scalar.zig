//! Scalar Turbo Strategy
//!
//! Single-threaded, CPU scalar implementation of turbo minification.
//! This strategy provides reliable performance across all systems without
//! requiring SIMD or multi-threading support.

const std = @import("std");
const interface = @import("../core/interface.zig");
const TurboStrategy = interface.TurboStrategy;
const TurboConfig = interface.TurboConfig;
const MinificationResult = interface.MinificationResult;
const StrategyType = interface.StrategyType;

/// Scalar strategy implementation
pub const ScalarStrategy = struct {
    const Self = @This();

    pub const strategy: TurboStrategy = TurboStrategy{
        .strategy_type = .scalar,
        .minifyFn = minify,
        .isAvailableFn = isAvailable,
        .estimatePerformanceFn = estimatePerformance,
    };

    /// Minify JSON using scalar processing
    fn minify(
        self: *const TurboStrategy,
        allocator: std.mem.Allocator,
        input: []const u8,
        config: TurboConfig,
    ) !MinificationResult {
        _ = self;
        _ = config;

        const start_time = std.time.microTimestamp();
        const initial_memory = getCurrentMemoryUsage();

        // Allocate output buffer (worst case: same size as input)
        const output = try allocator.alloc(u8, input.len);
        var output_len: usize = 0;

        // Simple scalar minification
        var in_string = false;
        var escape_next = false;

        for (input) |char| {
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

        const end_time = std.time.microTimestamp();
        const peak_memory = getCurrentMemoryUsage();

        // Resize output to actual size
        const final_output = try allocator.realloc(output, output_len);

        return MinificationResult{
            .output = final_output,
            .compression_ratio = 1.0 - (@as(f64, @floatFromInt(output_len)) / @as(f64, @floatFromInt(input.len))),
            .duration_us = @intCast(end_time - start_time),
            .peak_memory_bytes = peak_memory - initial_memory,
            .strategy_used = .scalar,
        };
    }

    /// Check if scalar strategy is available (always true)
    fn isAvailable() bool {
        return true;
    }

    /// Estimate performance for scalar strategy
    fn estimatePerformance(input_size: u64) u64 {
        // Conservative estimate: 500 MB/s for scalar processing
        const throughput_mbps = 500;
        return (input_size * throughput_mbps) / (1024 * 1024);
    }

    /// Get current memory usage (platform-specific implementation)
    fn getCurrentMemoryUsage() u64 {
        const builtin = @import("builtin");
        
        return switch (builtin.os.tag) {
            .linux => getLinuxMemoryUsage(),
            .macos => getMacOSMemoryUsage(),
            .windows => getWindowsMemoryUsage(),
            else => estimateProcessMemoryUsage(),
        };
    }
    
    /// Get memory usage on Linux using /proc/self/status
    fn getLinuxMemoryUsage() u64 {
        const file = std.fs.openFileAbsolute("/proc/self/status", .{}) catch return estimateProcessMemoryUsage();
        defer file.close();

        var buf: [4096]u8 = undefined;
        const bytes_read = file.read(&buf) catch return estimateProcessMemoryUsage();
        const content = buf[0..bytes_read];

        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "VmRSS:")) {
                const value_start = std.mem.indexOf(u8, line, ":") orelse continue;
                const value_str = std.mem.trim(u8, line[value_start + 1 ..], " \t");
                const kb_start = std.mem.indexOf(u8, value_str, " ") orelse continue;
                const kb_str = value_str[0..kb_start];
                const kb = std.fmt.parseInt(u64, kb_str, 10) catch return estimateProcessMemoryUsage();
                return kb * 1024; // Convert KB to bytes
            }
        }
        return estimateProcessMemoryUsage();
    }
    
    /// Get memory usage on macOS (placeholder)
    fn getMacOSMemoryUsage() u64 {
        return estimateProcessMemoryUsage();
    }
    
    /// Get memory usage on Windows (placeholder)
    fn getWindowsMemoryUsage() u64 {
        return estimateProcessMemoryUsage();
    }
    
    /// Estimate process memory usage (fallback)
    fn estimateProcessMemoryUsage() u64 {
        return 16 * 1024 * 1024; // 16MB estimate for scalar strategy
    }
};
