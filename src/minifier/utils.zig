const std = @import("std");

// Utility functions for JSON parsing and minification

/// Check if a byte is JSON whitespace (optimized with switch for better codegen)
pub inline fn isWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r' => true,
        else => false,
    };
}

pub fn isHexDigit(byte: u8) bool {
    return (byte >= '0' and byte <= '9') or
        (byte >= 'a' and byte <= 'f') or
        (byte >= 'A' and byte <= 'F');
}

// SIMD-optimized whitespace skipping
pub fn skipWhitespaceSimd(input: []const u8, start: usize) usize {
    var pos = start;
    const chunk_size = 32;

    // Process 32 bytes at a time with SIMD
    while (pos + chunk_size <= input.len) {
        const chunk: std.meta.Vector(32, u8) = input[pos .. pos + chunk_size][0..32].*;
        const spaces = @as(std.meta.Vector(32, u8), @splat(' '));
        const tabs = @as(std.meta.Vector(32, u8), @splat('\t'));
        const newlines = @as(std.meta.Vector(32, u8), @splat('\n'));
        const returns = @as(std.meta.Vector(32, u8), @splat('\r'));

        const is_space = chunk == spaces;
        const is_tab = chunk == tabs;
        const is_newline = chunk == newlines;
        const is_return = chunk == returns;

        const is_whitespace = is_space | is_tab | is_newline | is_return;

        // Find first non-whitespace
        const mask = @as(u32, @bitCast(is_whitespace));
        if (mask != 0xFFFFFFFF) {
            return pos + @ctz(~mask);
        }
        pos += chunk_size;
    }

    // Handle remaining bytes
    while (pos < input.len and isWhitespace(input[pos])) {
        pos += 1;
    }
    return pos;
}
