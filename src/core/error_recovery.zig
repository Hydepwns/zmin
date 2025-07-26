//! Error Recovery System
//!
//! This module implements automatic error recovery strategies for resilient
//! JSON minification even in the face of errors or resource constraints.

const std = @import("std");
const errors = @import("errors.zig");
const modes = @import("../modes/mod.zig");

/// Recovery result after attempting a strategy
pub const RecoveryResult = struct {
    /// Whether recovery was successful
    success: bool,
    /// The strategy that was used
    strategy: errors.RecoveryStrategy,
    /// New configuration after recovery
    config: ?RecoveryConfig = null,
    /// Performance impact of recovery (0.0 to 1.0)
    performance_impact: f64 = 0.0,
    /// Details about the recovery
    details: []const u8,
};

/// Configuration adjustments for recovery
pub const RecoveryConfig = struct {
    /// Processing mode to use
    mode: modes.ProcessingMode = .eco,
    /// Maximum memory to use
    max_memory: ?usize = null,
    /// Thread count to use
    thread_count: ?u32 = null,
    /// Chunk size for processing
    chunk_size: ?usize = null,
    /// Disable SIMD optimizations
    disable_simd: bool = false,
    /// Disable parallel processing
    disable_parallel: bool = false,
    /// Use streaming mode
    use_streaming: bool = false,
};

/// Recovery executor that applies strategies
pub const RecoveryExecutor = struct {
    allocator: std.mem.Allocator,
    error_handler: *errors.ErrorHandler,
    max_attempts: u32,
    current_attempt: u32 = 0,
    
    /// Initialize recovery executor
    pub fn init(
        allocator: std.mem.Allocator,
        error_handler: *errors.ErrorHandler,
        max_attempts: u32,
    ) RecoveryExecutor {
        return RecoveryExecutor{
            .allocator = allocator,
            .error_handler = error_handler,
            .max_attempts = max_attempts,
        };
    }
    
    /// Execute recovery for an error
    pub fn recover(
        self: *RecoveryExecutor,
        err: anyerror,
        context: errors.ErrorContext,
    ) !RecoveryResult {
        self.current_attempt += 1;
        
        if (self.current_attempt > self.max_attempts) {
            return RecoveryResult{
                .success = false,
                .strategy = .fail_fast,
                .details = "Maximum recovery attempts exceeded",
            };
        }
        
        // Get appropriate recovery strategy
        const strategy = errors.RecoveryStrategy.forError(err);
        
        // Log recovery attempt
        const recovery_context = errors.ErrorContext.init(
            err,
            .info,
            "Recovery attempt"
        ).withDetails(
            try std.fmt.allocPrint(
                self.allocator,
                "Attempting recovery strategy: {s}",
                .{strategy.getDescription()}
            )
        );
        try self.error_handler.handle(recovery_context);
        
        // Execute recovery strategy
        return switch (strategy) {
            .fail_fast => self.failFast(err),
            .fallback_to_eco_mode => self.fallbackToEco(err),
            .fallback_to_scalar => self.fallbackToScalar(err),
            .retry_with_reduced_parallelism => self.reduceParallelism(err),
            .retry_with_smaller_chunks => self.reducerChunkSize(err),
            .skip_optimizations => self.skipOptimizations(err),
            .use_streaming => self.useStreaming(err),
        };
    }
    
    fn failFast(self: *RecoveryExecutor, err: anyerror) RecoveryResult {
        _ = self;
        _ = err;
        return RecoveryResult{
            .success = false,
            .strategy = .fail_fast,
            .details = "No recovery attempted - failing fast",
        };
    }
    
    fn fallbackToEco(self: *RecoveryExecutor, err: anyerror) RecoveryResult {
        _ = self;
        _ = err;
        return RecoveryResult{
            .success = true,
            .strategy = .fallback_to_eco_mode,
            .config = RecoveryConfig{
                .mode = .eco,
                .max_memory = 64 * 1024, // 64KB
                .disable_simd = true,
                .disable_parallel = true,
            },
            .performance_impact = 0.7, // ECO is ~30% slower than TURBO
            .details = "Switched to ECO mode for minimal memory usage",
        };
    }
    
    fn fallbackToScalar(self: *RecoveryExecutor, err: anyerror) RecoveryResult {
        _ = self;
        _ = err;
        return RecoveryResult{
            .success = true,
            .strategy = .fallback_to_scalar,
            .config = RecoveryConfig{
                .disable_simd = true,
                .disable_parallel = true,
                .thread_count = 1,
            },
            .performance_impact = 0.5, // Scalar is ~50% slower than SIMD
            .details = "Disabled SIMD optimizations, using scalar processing",
        };
    }
    
    fn reduceParallelism(self: *RecoveryExecutor, err: anyerror) RecoveryResult {
        _ = err;
        
        // Calculate reduced thread count
        const current_threads = std.Thread.getCpuCount() catch 4;
        const new_threads = @max(1, current_threads / 2);
        
        return RecoveryResult{
            .success = true,
            .strategy = .retry_with_reduced_parallelism,
            .config = RecoveryConfig{
                .thread_count = new_threads,
            },
            .performance_impact = @as(f64, @floatFromInt(new_threads)) / 
                                @as(f64, @floatFromInt(current_threads)),
            .details = try std.fmt.allocPrint(
                self.allocator,
                "Reduced thread count from {d} to {d}",
                .{ current_threads, new_threads }
            ),
        };
    }
    
    fn reducerChunkSize(self: *RecoveryExecutor, err: anyerror) RecoveryResult {
        _ = self;
        _ = err;
        
        const new_chunk_size = 256 * 1024; // 256KB chunks
        
        return RecoveryResult{
            .success = true,
            .strategy = .retry_with_smaller_chunks,
            .config = RecoveryConfig{
                .chunk_size = new_chunk_size,
            },
            .performance_impact = 0.9, // ~10% slower with smaller chunks
            .details = "Reduced chunk size to 256KB for lower memory pressure",
        };
    }
    
    fn skipOptimizations(self: *RecoveryExecutor, err: anyerror) RecoveryResult {
        _ = self;
        _ = err;
        return RecoveryResult{
            .success = true,
            .strategy = .skip_optimizations,
            .config = RecoveryConfig{
                .disable_simd = true,
                .thread_count = 1,
                .mode = .sport, // Use balanced mode
            },
            .performance_impact = 0.6, // ~40% slower without optimizations
            .details = "Disabled all optimizations for maximum compatibility",
        };
    }
    
    fn useStreaming(self: *RecoveryExecutor, err: anyerror) RecoveryResult {
        _ = self;
        _ = err;
        return RecoveryResult{
            .success = true,
            .strategy = .use_streaming,
            .config = RecoveryConfig{
                .use_streaming = true,
                .max_memory = 1024 * 1024, // 1MB buffer
                .chunk_size = 64 * 1024, // 64KB chunks
            },
            .performance_impact = 0.7, // ~30% slower in streaming mode
            .details = "Switched to streaming mode for large file processing",
        };
    }
    
    /// Apply recovery configuration
    pub fn applyConfig(config: RecoveryConfig) modes.ModeConfig {
        var mode_config = modes.ModeConfig.fromMode(config.mode);
        
        if (config.max_memory) |max_mem| {
            mode_config.chunk_size = @min(mode_config.chunk_size, max_mem);
        }
        
        if (config.thread_count) |threads| {
            mode_config.parallel_chunks = threads;
        }
        
        if (config.chunk_size) |chunk| {
            mode_config.chunk_size = chunk;
        }
        
        if (config.disable_simd) {
            mode_config.enable_simd = false;
        }
        
        if (config.disable_parallel) {
            mode_config.parallel_chunks = 1;
        }
        
        return mode_config;
    }
};

/// Resilient minifier that automatically recovers from errors
pub const ResilientMinifier = struct {
    allocator: std.mem.Allocator,
    error_handler: errors.ErrorHandler,
    recovery_executor: RecoveryExecutor,
    
    /// Initialize resilient minifier
    pub fn init(allocator: std.mem.Allocator) ResilientMinifier {
        var error_handler = errors.ErrorHandler.init(
            allocator,
            errors.ErrorConfig{
                .enable_recovery = true,
                .max_recovery_attempts = 3,
            }
        );
        
        return ResilientMinifier{
            .allocator = allocator,
            .error_handler = error_handler,
            .recovery_executor = RecoveryExecutor.init(
                allocator,
                &error_handler,
                3
            ),
        };
    }
    
    /// Deinitialize resilient minifier
    pub fn deinit(self: *ResilientMinifier) void {
        self.error_handler.deinit();
    }
    
    /// Minify JSON with automatic error recovery
    pub fn minify(
        self: *ResilientMinifier,
        input: []const u8,
        initial_mode: modes.ProcessingMode,
    ) !MinificationResult {
        var current_config = modes.ModeConfig.fromMode(initial_mode);
        var attempt: u32 = 0;
        
        while (attempt < 3) : (attempt += 1) {
            // Attempt minification
            const result = self.attemptMinification(input, current_config) catch |err| {
                // Create error context
                const context = errors.ErrorContext.init(
                    err,
                    .error,
                    "JSON minification"
                ).withDetails(
                    try std.fmt.allocPrint(
                        self.allocator,
                        "Attempt {d} failed with mode {s}",
                        .{ attempt + 1, @tagName(current_config.mode) }
                    )
                );
                
                // Handle error
                try self.error_handler.handle(context);
                
                // Attempt recovery
                const recovery = try self.recovery_executor.recover(err, context);
                
                if (!recovery.success) {
                    return err;
                }
                
                // Apply recovery configuration
                if (recovery.config) |recovery_config| {
                    current_config = RecoveryExecutor.applyConfig(recovery_config);
                }
                
                // Track recovery in stats
                self.error_handler.stats.recovered_errors += 1;
                
                continue;
            };
            
            // Success!
            return MinificationResult{
                .output = result,
                .mode_used = current_config.mode,
                .recovery_attempts = attempt,
                .final_config = current_config,
            };
        }
        
        return error.MaxRecoveryAttemptsExceeded;
    }
    
    fn attemptMinification(
        self: *ResilientMinifier,
        input: []const u8,
        config: modes.ModeConfig,
    ) ![]u8 {
        // This would call the actual minification logic
        // For now, simulate potential errors
        _ = self;
        _ = input;
        _ = config;
        
        // TODO: Implement actual minification call
        return error.NotImplemented;
    }
};

/// Result of resilient minification
pub const MinificationResult = struct {
    /// Minified output
    output: []u8,
    /// Mode that succeeded
    mode_used: modes.ProcessingMode,
    /// Number of recovery attempts
    recovery_attempts: u32,
    /// Final configuration used
    final_config: modes.ModeConfig,
};

// Tests
test "recovery strategy selection" {
    const executor = RecoveryExecutor.init(
        std.testing.allocator,
        undefined,
        3
    );
    
    const result = executor.fallbackToEco(error.OutOfMemory);
    try std.testing.expect(result.success);
    try std.testing.expectEqual(modes.ProcessingMode.eco, result.config.?.mode);
}

test "recovery config application" {
    const config = RecoveryConfig{
        .mode = .eco,
        .thread_count = 2,
        .disable_simd = true,
    };
    
    const mode_config = RecoveryExecutor.applyConfig(config);
    try std.testing.expectEqual(@as(usize, 2), mode_config.parallel_chunks);
    try std.testing.expect(!mode_config.enable_simd);
}