//! Common Minifier Interface
//!
//! This module defines the standard interface that all minifier implementations
//! must follow, ensuring consistency across the codebase and reducing duplication.

const std = @import("std");
const errors = @import("errors.zig");

/// Standard result type for minification operations
pub const MinifyResult = struct {
    /// Number of bytes written to output
    bytes_written: usize,
    /// Performance statistics (optional)
    stats: ?PerformanceStats = null,
};

/// Performance statistics for minification
pub const PerformanceStats = struct {
    /// Processing time in nanoseconds
    processing_time_ns: u64 = 0,
    /// Bytes processed per second
    throughput_bps: f64 = 0,
    /// Memory peak usage
    peak_memory_bytes: usize = 0,
    /// Strategy used (for adaptive minifiers)
    strategy_used: []const u8 = "default",
};

/// Common minifier interface that all implementations should follow
pub const MinifierInterface = struct {
    /// Type-erased pointer to the actual implementation
    ptr: *anyopaque,
    /// Virtual function table
    vtable: *const VTable,

    pub const VTable = struct {
        /// Minify JSON from input to output buffer
        minify: *const fn (ptr: *anyopaque, input: []const u8, output: []u8) anyerror!MinifyResult,
        /// Minify with writer interface
        minifyWriter: *const fn (ptr: *anyopaque, input: []const u8, writer: anytype) anyerror!MinifyResult,
        /// Reset internal state
        reset: *const fn (ptr: *anyopaque) void,
        /// Get capabilities/features
        getCapabilities: *const fn (ptr: *anyopaque) Capabilities,
    };

    /// Minify JSON from input to output buffer
    pub fn minify(self: MinifierInterface, input: []const u8, output: []u8) !MinifyResult {
        return self.vtable.minify(self.ptr, input, output);
    }

    /// Minify JSON to a writer
    pub fn minifyWriter(self: MinifierInterface, input: []const u8, writer: anytype) !MinifyResult {
        return self.vtable.minifyWriter(self.ptr, input, writer);
    }

    /// Reset internal state
    pub fn reset(self: MinifierInterface) void {
        self.vtable.reset(self.ptr);
    }

    /// Get minifier capabilities
    pub fn getCapabilities(self: MinifierInterface) Capabilities {
        return self.vtable.getCapabilities(self.ptr);
    }
};

/// Minifier capabilities/features
pub const Capabilities = struct {
    /// Supports SIMD acceleration
    supports_simd: bool = false,
    /// Supports parallel processing
    supports_parallel: bool = false,
    /// Supports streaming mode
    supports_streaming: bool = false,
    /// Maximum recommended input size (0 = no limit)
    max_input_size: usize = 0,
    /// Preferred chunk size for optimal performance
    preferred_chunk_size: usize = 64 * 1024,
    /// Name of the implementation
    name: []const u8 = "unknown",
};

/// Helper to create MinifierInterface from concrete type
pub fn createInterface(comptime T: type, impl: *T) MinifierInterface {
    const vtable = struct {
        fn minify(ptr: *anyopaque, input: []const u8, output: []u8) anyerror!MinifyResult {
            const self: *T = @ptrCast(@alignCast(ptr));
            if (@hasDecl(T, "minify")) {
                const result = try self.minify(input, output);
                if (@TypeOf(result) == usize) {
                    return MinifyResult{ .bytes_written = result };
                } else {
                    return result;
                }
            } else {
                return error.MethodNotImplemented;
            }
        }

        fn minifyWriter(ptr: *anyopaque, input: []const u8, writer: anytype) anyerror!MinifyResult {
            const self: *T = @ptrCast(@alignCast(ptr));
            if (@hasDecl(T, "minifyWriter")) {
                const result = try self.minifyWriter(input, writer);
                if (@TypeOf(result) == usize) {
                    return MinifyResult{ .bytes_written = result };
                } else {
                    return result;
                }
            } else {
                return error.MethodNotImplemented;
            }
        }

        fn reset(ptr: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            if (@hasDecl(T, "reset")) {
                self.reset();
            }
        }

        fn getCapabilities(ptr: *anyopaque) Capabilities {
            const self: *T = @ptrCast(@alignCast(ptr));
            if (@hasDecl(T, "getCapabilities")) {
                return self.getCapabilities();
            } else {
                return Capabilities{ .name = @typeName(T) };
            }
        }
    };

    return MinifierInterface{
        .ptr = @ptrCast(impl),
        .vtable = &.{
            .minify = vtable.minify,
            .minifyWriter = vtable.minifyWriter,
            .reset = vtable.reset,
            .getCapabilities = vtable.getCapabilities,
        },
    };
}

/// Base minifier implementation that others can extend
pub const BaseMinifier = struct {
    allocator: std.mem.Allocator,
    capabilities: Capabilities = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn reset(self: *Self) void {
        _ = self;
    }

    pub fn getCapabilities(self: *const Self) Capabilities {
        return self.capabilities;
    }
};

/// Common configuration base that can be extended
pub const MinifierConfig = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,
    /// Enable input validation
    validate_input: bool = true,
    /// Preserve number precision
    preserve_precision: bool = true,
    /// Buffer size for operations
    buffer_size: usize = 64 * 1024,
    /// Enable performance monitoring
    enable_monitoring: bool = false,
    /// Maximum threads (0 = auto-detect)
    max_threads: usize = 0,
    /// Enable SIMD optimizations
    enable_simd: bool = true,
};

/// Factory function type for creating minifiers
pub const MinifierFactory = fn (config: MinifierConfig) anyerror!MinifierInterface;

/// Registry for available minifier implementations
pub const MinifierRegistry = struct {
    entries: std.StringHashMap(MinifierFactory),

    pub fn init(allocator: std.mem.Allocator) MinifierRegistry {
        return .{
            .entries = std.StringHashMap(MinifierFactory).init(allocator),
        };
    }

    pub fn deinit(self: *MinifierRegistry) void {
        self.entries.deinit();
    }

    pub fn register(self: *MinifierRegistry, name: []const u8, factory: MinifierFactory) !void {
        try self.entries.put(name, factory);
    }

    pub fn create(self: *MinifierRegistry, name: []const u8, config: MinifierConfig) !MinifierInterface {
        if (self.entries.get(name)) |factory| {
            return try factory(config);
        }
        return error.MinifierNotFound;
    }

    pub fn list(self: *MinifierRegistry) []const []const u8 {
        return self.entries.keys();
    }
};