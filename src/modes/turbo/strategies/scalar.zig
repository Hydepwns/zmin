//! Scalar Turbo Strategy
//!
//! Single-threaded, CPU scalar implementation of turbo minification.
//! This strategy provides reliable performance across all systems without
//! requiring SIMD or multi-threading support.

const std = @import("std");
const interface = @import("../core/interface.zig");
const LightweightValidator = @import("minifier").lightweight_validator.LightweightValidator;
const char_classification = @import("common").char_classification;
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
        const initial_memory = 0; // Memory tracking moved to profiling tools

        // Skip validation in turbo mode for performance and to allow trailing commas
        // try LightweightValidator.validate(input);

        // Allocate output buffer (worst case: same size as input)
        const output = try allocator.alloc(u8, input.len);
        
        // Use optimized branch-free character classification
        const output_len = char_classification.minifyCore(input, output);

        const end_time = std.time.microTimestamp();
        const peak_memory = 0; // Memory tracking moved to profiling tools

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

    // Memory tracking simplified - actual profiling should use dedicated tools
};
