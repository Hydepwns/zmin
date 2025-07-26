//! Turbo Mode Module
//!
//! This module provides the unified turbo minification system with automatic
//! strategy selection based on input characteristics and system capabilities.

const std = @import("std");
const interface = @import("core/interface.zig");

// Import all strategies
const scalar = @import("strategies/scalar.zig");
const simd = @import("strategies/simd.zig");
const parallel = @import("strategies/parallel.zig");
const streaming = @import("strategies/streaming.zig");

// Re-export core types
pub const TurboStrategy = interface.TurboStrategy;
pub const TurboConfig = interface.TurboConfig;
pub const MinificationResult = interface.MinificationResult;
pub const StrategyType = interface.StrategyType;
pub const SystemCapabilities = interface.SystemCapabilities;
pub const TurboError = interface.TurboError;

/// Turbo minifier with automatic strategy selection
pub const TurboMinifier = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    capabilities: SystemCapabilities,
    
    /// Initialize turbo minifier with system detection
    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .capabilities = try SystemCapabilities.detect(),
        };
    }
    
    /// Minify JSON with automatic strategy selection
    pub fn minify(self: *Self, input: []const u8, config: TurboConfig) !MinificationResult {
        const strategy = try self.selectOptimalStrategy(input, config);
        return strategy.minify(self.allocator, input, config);
    }
    
    /// Minify JSON with specific strategy
    pub fn minifyWithStrategy(
        self: *Self, 
        input: []const u8, 
        strategy_type: StrategyType,
        config: TurboConfig
    ) !MinificationResult {
        const strategy = try self.getStrategy(strategy_type);
        return strategy.minify(self.allocator, input, config);
    }
    
    /// Select optimal strategy based on input and system characteristics
    fn selectOptimalStrategy(self: *Self, input: []const u8, config: TurboConfig) !*const TurboStrategy {
        // If strategy is explicitly specified, use it
        if (config.strategy) |specified_strategy| {
            return self.getStrategy(specified_strategy);
        }
        
        const input_size = input.len;
        
        // Strategy selection logic
        if (config.max_memory_bytes) |max_memory| {
            if (input_size > max_memory) {
                // Must use streaming for memory-constrained scenarios
                return self.getStrategy(.streaming);
            }
        }
        
        // For small files, scalar is often fastest due to overhead
        if (input_size < 64 * 1024) {
            return self.getStrategy(.scalar);
        }
        
        // For medium files, prefer SIMD if available
        if (input_size < 10 * 1024 * 1024) {
            if (simd.SimdStrategy.strategy.isAvailable() and config.enable_simd) {
                return self.getStrategy(.simd);
            }
            return self.getStrategy(.scalar);
        }
        
        // For large files, prefer parallel if we have multiple cores
        if (self.capabilities.cpu_cores > 1 and parallel.ParallelStrategy.strategy.isAvailable()) {
            return self.getStrategy(.parallel);
        }
        
        // Fallback to SIMD or scalar
        if (simd.SimdStrategy.strategy.isAvailable() and config.enable_simd) {
            return self.getStrategy(.simd);
        }
        
        return self.getStrategy(.scalar);
    }
    
    /// Get strategy implementation by type
    fn getStrategy(self: *Self, strategy_type: StrategyType) !*const TurboStrategy {
        _ = self;
        
        return switch (strategy_type) {
            .scalar => &scalar.ScalarStrategy.strategy,
            .simd => blk: {
                if (!simd.SimdStrategy.strategy.isAvailable()) {
                    return TurboError.StrategyUnavailable;
                }
                break :blk &simd.SimdStrategy.strategy;
            },
            .parallel => blk: {
                if (!parallel.ParallelStrategy.strategy.isAvailable()) {
                    return TurboError.StrategyUnavailable;
                }
                break :blk &parallel.ParallelStrategy.strategy;
            },
            .streaming => &streaming.StreamingStrategy.strategy,
        };
    }
    
    /// Get all available strategies
    pub fn getAvailableStrategies(self: *Self) []StrategyType {
        _ = self;
        
        var strategies = std.ArrayList(StrategyType).init(self.allocator);
        defer strategies.deinit();
        
        // Scalar is always available
        strategies.append(.scalar) catch {};
        
        // Check other strategies
        if (simd.SimdStrategy.strategy.isAvailable()) {
            strategies.append(.simd) catch {};
        }
        
        if (parallel.ParallelStrategy.strategy.isAvailable()) {
            strategies.append(.parallel) catch {};
        }
        
        // Streaming is always available
        strategies.append(.streaming) catch {};
        
        return strategies.toOwnedSlice() catch &[_]StrategyType{.scalar};
    }
    
    /// Estimate performance for given input and strategy
    pub fn estimatePerformance(
        self: *Self, 
        input_size: u64, 
        strategy_type: StrategyType
    ) !u64 {
        const strategy = try self.getStrategy(strategy_type);
        return strategy.estimatePerformance(input_size);
    }
};