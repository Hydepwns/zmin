//! C API for zmin
//!
//! This module provides a C-compatible API for using zmin from other languages.

const std = @import("std");
const zmin = @import("../root.zig");

/// Result structure for C API
pub const ZminResult = extern struct {
    data: [*c]u8,
    size: usize,
    error_code: c_int,
};

/// Thread-local allocator for C API
threadlocal var c_allocator: ?std.mem.Allocator = null;

/// Initialize the C API
export fn zmin_init() void {
    // Use a general purpose allocator for C API
    c_allocator = std.heap.c_allocator;
}

/// Get version string
export fn zmin_get_version() [*c]const u8 {
    return "1.0.0";
}

/// Minify JSON with default mode (SPORT)
export fn zmin_minify(input: [*c]const u8, input_size: usize) ZminResult {
    return zmin_minify_mode(input, input_size, 1); // 1 = SPORT
}

/// Minify JSON with specified mode
/// mode: 0 = ECO, 1 = SPORT, 2 = TURBO
export fn zmin_minify_mode(input: [*c]const u8, input_size: usize, mode: c_int) ZminResult {
    const allocator = c_allocator orelse {
        return ZminResult{
            .data = null,
            .size = 0,
            .error_code = -99, // Not initialized
        };
    };

    // Convert mode
    const processing_mode = switch (mode) {
        0 => zmin.ProcessingMode.eco,
        1 => zmin.ProcessingMode.sport,
        2 => zmin.ProcessingMode.turbo,
        else => return ZminResult{
            .data = null,
            .size = 0,
            .error_code = -3, // Invalid mode
        },
    };

    // Get input slice
    const input_slice = input[0..input_size];

    // Minify
    const output = zmin.minifyWithMode(allocator, input_slice, processing_mode) catch |err| {
        const error_code: c_int = switch (err) {
            error.InvalidJson => -1,
            error.OutOfMemory => -2,
            else => -99,
        };

        return ZminResult{
            .data = null,
            .size = 0,
            .error_code = error_code,
        };
    };

    // Convert to C string (null-terminated)
    const c_output = allocator.allocSentinel(u8, output.len, 0) catch {
        allocator.free(output);
        return ZminResult{
            .data = null,
            .size = 0,
            .error_code = -2, // Out of memory
        };
    };

    @memcpy(c_output[0..output.len], output);
    allocator.free(output);

    return ZminResult{
        .data = c_output.ptr,
        .size = output.len,
        .error_code = 0,
    };
}

/// Validate JSON
/// Returns 0 for valid, error code for invalid
export fn zmin_validate(input: [*c]const u8, input_size: usize) c_int {
    const input_slice = input[0..input_size];

    zmin.validate(input_slice) catch |err| {
        return switch (err) {
            error.InvalidJson => -1,
            else => -99,
        };
    };

    return 0;
}

/// Free a result allocated by zmin
export fn zmin_free_result(result: *ZminResult) void {
    if (result.data != null and result.size > 0) {
        const allocator = c_allocator orelse return;
        const slice = result.data[0 .. result.size + 1]; // +1 for null terminator
        allocator.free(slice);
        result.data = null;
        result.size = 0;
    }
}

/// Get error message for error code
export fn zmin_get_error_message(error_code: c_int) [*c]const u8 {
    return switch (error_code) {
        0 => "No error",
        -1 => "Invalid JSON",
        -2 => "Out of memory",
        -3 => "Invalid mode",
        -99 => "Unknown error",
        else => "Unknown error code",
    };
}

/// Estimate output size for given input size
export fn zmin_estimate_output_size(input_size: usize) usize {
    // Conservative estimate: input size + some buffer
    return input_size + 1024;
}

// Additional helpers for specific language bindings

/// Create a new minifier instance (for languages that prefer object-oriented API)
export fn zmin_create_minifier(mode: c_int) ?*anyopaque {
    const allocator = c_allocator orelse return null;

    const minifier = allocator.create(MinifierState) catch return null;
    minifier.* = MinifierState{
        .mode = switch (mode) {
            0 => .eco,
            1 => .sport,
            2 => .turbo,
            else => .sport,
        },
        .allocator = allocator,
    };

    return @ptrCast(minifier);
}

/// Destroy a minifier instance
export fn zmin_destroy_minifier(minifier: ?*anyopaque) void {
    if (minifier) |ptr| {
        const state: *MinifierState = @ptrCast(@alignCast(ptr));
        state.allocator.destroy(state);
    }
}

/// Minify using a minifier instance
export fn zmin_minifier_minify(minifier: ?*anyopaque, input: [*c]const u8, input_size: usize) ZminResult {
    const ptr = minifier orelse return ZminResult{
        .data = null,
        .size = 0,
        .error_code = -99,
    };

    const state: *MinifierState = @ptrCast(@alignCast(ptr));
    return zmin_minify_mode(input, input_size, @intFromEnum(state.mode));
}

const MinifierState = struct {
    mode: zmin.ProcessingMode,
    allocator: std.mem.Allocator,
};
