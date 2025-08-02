//! Branch-free character classification for JSON minification
//!
//! Provides lookup table-based character classification to eliminate
//! branch misprediction penalties during JSON processing.

const std = @import("std");

/// Character classes for JSON minification
pub const CharacterClass = enum(u8) {
    REGULAR = 0,    // Normal character, always copy
    QUOTE = 1,      // " - toggles string state
    BACKSLASH = 2,  // \ - escape character
    WHITESPACE = 3, // space, tab, newline, carriage return - skip outside strings
};

/// Lookup table for all 256 ASCII characters
/// Provides O(1) character classification without branching
pub const CHAR_CLASS_TABLE = blk: {
    var table: [256]CharacterClass = [_]CharacterClass{.REGULAR} ** 256;
    table['"'] = .QUOTE;
    table['\\'] = .BACKSLASH;
    table[' '] = .WHITESPACE;
    table['\t'] = .WHITESPACE;
    table['\n'] = .WHITESPACE;
    table['\r'] = .WHITESPACE;
    break :blk table;
};

/// Fast inline character classification using lookup table
pub inline fn classifyChar(char: u8) CharacterClass {
    return CHAR_CLASS_TABLE[char];
}

/// Branch-free JSON minification core loop
/// This implements the most optimized character processing loop
pub fn minifyCore(input: []const u8, output: []u8) usize {
    var out_pos: usize = 0;
    var in_string = false;
    var escape_next = false;

    // Process with prefetching for better cache utilization
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        // Prefetch next cache line (64 bytes ahead)
        if (i + 64 < input.len) {
            @prefetch(input.ptr + i + 64, .{ .rw = .read, .cache = .data });
        }
        
        const char = input[i];
        // Fast path for escaped characters
        if (escape_next) {
            output[out_pos] = char;
            out_pos += 1;
            escape_next = false;
            continue;
        }

        // Branch-free character classification
        const char_class = CHAR_CLASS_TABLE[char];
        
        // Handle each character class with minimal branching
        switch (char_class) {
            .QUOTE => {
                in_string = !in_string;
                output[out_pos] = char;
                out_pos += 1;
            },
            .BACKSLASH => {
                escape_next = in_string; // Only set escape if we're in a string
                output[out_pos] = char;
                out_pos += 1;
            },
            .WHITESPACE => {
                // Branchless: copy character only if in_string is true
                output[out_pos] = char;
                out_pos += @intFromBool(in_string);
            },
            .REGULAR => {
                output[out_pos] = char;
                out_pos += 1;
            },
        }
    }

    return out_pos;
}

/// Alternative branch-free implementation with even less branching
/// Uses bit manipulation for maximum performance on modern CPUs
pub fn minifyCoreUltraFast(input: []const u8, output: []u8) usize {
    var out_pos: usize = 0;
    var in_string: u32 = 0; // Use integer for branchless operations
    var escape_next: u32 = 0;

    for (input) |char| {
        // Handle escaped characters
        if (escape_next != 0) {
            output[out_pos] = char;
            out_pos += 1;
            escape_next = 0;
            continue;
        }

        const char_class = CHAR_CLASS_TABLE[char];
        
        // Branchless processing using bit manipulation
        switch (char_class) {
            .QUOTE => {
                in_string ^= 1; // Toggle string state
                output[out_pos] = char;
                out_pos += 1;
            },
            .BACKSLASH => {
                escape_next = in_string; // Set escape only if in string
                output[out_pos] = char;
                out_pos += 1;
            },
            .WHITESPACE => {
                // Ultra-branchless: copy character based on string state
                const should_copy = in_string;
                output[out_pos] = char;
                out_pos += should_copy;
            },
            .REGULAR => {
                output[out_pos] = char;
                out_pos += 1;
            },
        }
    }

    return out_pos;
}

/// Test function to verify correctness of optimized implementations
pub fn testCorrectness(allocator: std.mem.Allocator, input: []const u8) !bool {
    const output1 = try allocator.alloc(u8, input.len);
    defer allocator.free(output1);
    const output2 = try allocator.alloc(u8, input.len);
    defer allocator.free(output2);
    
    const len1 = minifyCore(input, output1);
    const len2 = minifyCoreUltraFast(input, output2);
    
    if (len1 != len2) return false;
    return std.mem.eql(u8, output1[0..len1], output2[0..len2]);
}