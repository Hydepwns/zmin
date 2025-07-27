//! WebAssembly exports for zmin
//!
//! This module provides WebAssembly-compatible exports for using zmin
//! in web browsers and Node.js environments.

const std = @import("std");
const zmin = @import("../root.zig");

/// Global allocator for WASM (uses a fixed buffer)
var wasm_buffer: [16 * 1024 * 1024]u8 = undefined; // 16MB buffer
var wasm_fba = std.heap.FixedBufferAllocator.init(&wasm_buffer);
var wasm_allocator = wasm_fba.allocator();

/// Result structure for WASM calls
const WasmResult = extern struct {
    ptr: [*]u8,
    len: u32,
    error_code: i32,
};

/// Error codes for WASM
const WasmError = enum(i32) {
    none = 0,
    invalid_json = -1,
    out_of_memory = -2,
    invalid_mode = -3,
    buffer_too_small = -4,
    unknown_error = -99,
};

/// Initialize the WASM module
export fn zmin_init() void {
    // Reset the allocator
    wasm_fba.reset();
}

/// Get the version string
export fn zmin_version() [*:0]const u8 {
    return "1.0.0";
}

/// Minify JSON with default mode (SPORT)
export fn zmin_minify(input_ptr: [*]const u8, input_len: u32) WasmResult {
    return minifyWithMode(input_ptr, input_len, 1); // 1 = SPORT mode
}

/// Minify JSON with specified mode
/// mode: 0 = ECO, 1 = SPORT, 2 = TURBO
export fn zmin_minify_mode(input_ptr: [*]const u8, input_len: u32, mode: i32) WasmResult {
    return minifyWithMode(input_ptr, input_len, mode);
}

/// Validate JSON without minifying
/// Returns 0 for valid, error code for invalid
export fn zmin_validate(input_ptr: [*]const u8, input_len: u32) i32 {
    const input = input_ptr[0..input_len];

    zmin.validate(input) catch |err| {
        return switch (err) {
            error.InvalidJson => @intFromEnum(WasmError.invalid_json),
            else => @intFromEnum(WasmError.unknown_error),
        };
    };

    return 0;
}

/// Free allocated memory
export fn zmin_free(ptr: [*]u8, len: u32) void {
    const slice = ptr[0..len];
    wasm_allocator.free(slice);
}

/// Get last error message
export fn zmin_get_error_message(error_code: i32) [*:0]const u8 {
    return switch (error_code) {
        0 => "No error",
        -1 => "Invalid JSON",
        -2 => "Out of memory",
        -3 => "Invalid mode",
        -4 => "Buffer too small",
        else => "Unknown error",
    };
}

/// Allocate memory for use by the host
export fn zmin_alloc(size: u32) ?[*]u8 {
    const slice = wasm_allocator.alloc(u8, size) catch return null;
    return slice.ptr;
}

/// Get the recommended output buffer size for a given input size
export fn zmin_estimate_output_size(input_size: u32) u32 {
    // Minification typically reduces size by 10-30%
    // But we allocate a bit extra for safety
    return input_size + 1024;
}

/// Get memory usage statistics
export fn zmin_get_memory_usage() u32 {
    return @intCast(wasm_fba.end_index);
}

/// Get maximum available memory
export fn zmin_get_max_memory() u32 {
    return wasm_buffer.len;
}

// Internal helper function
fn minifyWithMode(input_ptr: [*]const u8, input_len: u32, mode_int: i32) WasmResult {
    const input = input_ptr[0..input_len];

    // Validate mode
    const mode = switch (mode_int) {
        0 => zmin.ProcessingMode.eco,
        1 => zmin.ProcessingMode.sport,
        2 => zmin.ProcessingMode.turbo,
        else => return WasmResult{
            .ptr = undefined,
            .len = 0,
            .error_code = @intFromEnum(WasmError.invalid_mode),
        },
    };

    // For ECO mode in WASM, create a smaller allocator
    const allocator = if (mode == .eco) blk: {
        // ECO mode gets its own 64KB allocator
        const eco_buffer = wasm_allocator.alloc(u8, 64 * 1024) catch {
            return WasmResult{
                .ptr = undefined,
                .len = 0,
                .error_code = @intFromEnum(WasmError.out_of_memory),
            };
        };
        var eco_fba = std.heap.FixedBufferAllocator.init(eco_buffer);
        break :blk eco_fba.allocator();
    } else wasm_allocator;

    // Minify
    const output = zmin.minifyWithMode(allocator, input, mode) catch |err| {
        const error_code = switch (err) {
            error.InvalidJson => WasmError.invalid_json,
            error.OutOfMemory => WasmError.out_of_memory,
            else => WasmError.unknown_error,
        };

        return WasmResult{
            .ptr = undefined,
            .len = 0,
            .error_code = @intFromEnum(error_code),
        };
    };

    return WasmResult{
        .ptr = output.ptr,
        .len = @intCast(output.len),
        .error_code = 0,
    };
}

// WebAssembly-specific panic handler
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;
    _ = ret_addr;

    // Write panic message to a known location for debugging
    const panic_msg = "PANIC: ";
    const max_len = @min(msg.len, 256);

    if (wasm_allocator.alloc(u8, panic_msg.len + max_len)) |panic_buffer| {
        @memcpy(panic_buffer[0..panic_msg.len], panic_msg);
        @memcpy(panic_buffer[panic_msg.len..][0..max_len], msg[0..max_len]);
    } else |_| {}

    @trap();
}
