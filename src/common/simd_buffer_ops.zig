//! SIMD-Accelerated Buffer Operations
//!
//! This module provides SIMD-optimized versions of common buffer operations
//! for improved performance on supported platforms.

const std = @import("std");
const builtin = @import("builtin");
const constants = @import("constants.zig");
const simd_detector = @import("../platform/simd_detector.zig");

/// SIMD-accelerated memory operations
pub const SimdOps = struct {
    /// Find first occurrence of byte using SIMD
    pub fn findByte(haystack: []const u8, needle: u8) ?usize {
        const features = simd_detector.detect();
        
        // Use SIMD for large buffers
        if (haystack.len >= 32 and features.getBestSimdLevel() != .none) {
            return findByteSimd(haystack, needle, features);
        }
        
        // Fallback to scalar
        return findByteScalar(haystack, needle);
    }
    
    /// Count occurrences of byte using SIMD
    pub fn countByte(buffer: []const u8, byte: u8) usize {
        const features = simd_detector.detect();
        
        if (buffer.len >= 32 and features.getBestSimdLevel() != .none) {
            return countByteSimd(buffer, byte, features);
        }
        
        return countByteScalar(buffer, byte);
    }
    
    /// Check if all bytes are equal using SIMD
    pub fn allBytesEqual(buffer: []const u8, value: u8) bool {
        const features = simd_detector.detect();
        
        if (buffer.len >= 32 and features.getBestSimdLevel() != .none) {
            return allBytesEqualSimd(buffer, value, features);
        }
        
        return allBytesEqualScalar(buffer, value);
    }
    
    /// Copy with SIMD alignment
    pub fn copyAligned(dest: []u8, src: []const u8) void {
        const features = simd_detector.detect();
        
        if (src.len >= 64 and features.getBestSimdLevel() != .none) {
            copyAlignedSimd(dest, src, features);
        } else {
            @memcpy(dest, src);
        }
    }
    
    /// Fill buffer with pattern using SIMD
    pub fn fillPattern(buffer: []u8, pattern: []const u8) void {
        const features = simd_detector.detect();
        
        if (buffer.len >= 64 and pattern.len <= 16 and features.getBestSimdLevel() != .none) {
            fillPatternSimd(buffer, pattern, features);
        } else {
            fillPatternScalar(buffer, pattern);
        }
    }
};

// Scalar implementations
fn findByteScalar(haystack: []const u8, needle: u8) ?usize {
    for (haystack, 0..) |byte, i| {
        if (byte == needle) return i;
    }
    return null;
}

fn countByteScalar(buffer: []const u8, byte: u8) usize {
    var count: usize = 0;
    for (buffer) |b| {
        if (b == byte) count += 1;
    }
    return count;
}

fn allBytesEqualScalar(buffer: []const u8, value: u8) bool {
    for (buffer) |byte| {
        if (byte != value) return false;
    }
    return true;
}

fn fillPatternScalar(buffer: []u8, pattern: []const u8) void {
    if (pattern.len == 0) return;
    
    var pos: usize = 0;
    while (pos < buffer.len) {
        const chunk_size = @min(pattern.len, buffer.len - pos);
        @memcpy(buffer[pos..pos + chunk_size], pattern[0..chunk_size]);
        pos += chunk_size;
    }
}

// SIMD implementations
fn findByteSimd(haystack: []const u8, needle: u8, features: simd_detector.CpuFeatures) ?usize {
    const vector_size = features.getBestSimdLevel().getVectorSize();
    
    // Process aligned chunks with SIMD
    var pos: usize = 0;
    const needle_vec = @as(@Vector(vector_size, u8), @splat(needle));
    
    while (pos + vector_size <= haystack.len) {
        const chunk: @Vector(vector_size, u8) = haystack[pos..][0..vector_size].*;
        const matches = chunk == needle_vec;
        
        // Check if any match
        if (@reduce(.Or, matches)) {
            // Find first match in vector
            inline for (0..vector_size) |i| {
                if (matches[i]) {
                    return pos + i;
                }
            }
        }
        
        pos += vector_size;
    }
    
    // Process remainder
    return findByteScalar(haystack[pos..], needle);
}

fn countByteSimd(buffer: []const u8, byte: u8, features: simd_detector.CpuFeatures) usize {
    const vector_size = features.getBestSimdLevel().getVectorSize();
    var count: usize = 0;
    var pos: usize = 0;
    
    const byte_vec = @as(@Vector(vector_size, u8), @splat(byte));
    
    // Process aligned chunks
    while (pos + vector_size <= buffer.len) {
        const chunk: @Vector(vector_size, u8) = buffer[pos..][0..vector_size].*;
        const matches = chunk == byte_vec;
        
        // Count matches in vector
        const match_count = @reduce(.Add, @select(u8, matches, 
            @as(@Vector(vector_size, u8), @splat(1)), 
            @as(@Vector(vector_size, u8), @splat(0))
        ));
        count += match_count;
        
        pos += vector_size;
    }
    
    // Process remainder
    count += countByteScalar(buffer[pos..], byte);
    return count;
}

fn allBytesEqualSimd(buffer: []const u8, value: u8, features: simd_detector.CpuFeatures) bool {
    const vector_size = features.getBestSimdLevel().getVectorSize();
    var pos: usize = 0;
    
    const value_vec = @as(@Vector(vector_size, u8), @splat(value));
    
    // Process aligned chunks
    while (pos + vector_size <= buffer.len) {
        const chunk: @Vector(vector_size, u8) = buffer[pos..][0..vector_size].*;
        const matches = chunk == value_vec;
        
        if (!@reduce(.And, matches)) {
            return false;
        }
        
        pos += vector_size;
    }
    
    // Check remainder
    return allBytesEqualScalar(buffer[pos..], value);
}

fn copyAlignedSimd(dest: []u8, src: []const u8, features: simd_detector.CpuFeatures) void {
    const vector_size = features.getBestSimdLevel().getVectorSize();
    var pos: usize = 0;
    
    // Check alignment
    const src_aligned = (@intFromPtr(src.ptr) & (vector_size - 1)) == 0;
    const dest_aligned = (@intFromPtr(dest.ptr) & (vector_size - 1)) == 0;
    
    if (src_aligned and dest_aligned) {
        // Fast path: both aligned
        while (pos + vector_size <= src.len) {
            const chunk: @Vector(vector_size, u8) = src[pos..][0..vector_size].*;
            dest[pos..][0..vector_size].* = chunk;
            pos += vector_size;
        }
    } else {
        // Slow path: unaligned
        while (pos + vector_size <= src.len) {
            var chunk: @Vector(vector_size, u8) = undefined;
            for (0..vector_size) |i| {
                chunk[i] = src[pos + i];
            }
            for (0..vector_size) |i| {
                dest[pos + i] = chunk[i];
            }
            pos += vector_size;
        }
    }
    
    // Copy remainder
    if (pos < src.len) {
        @memcpy(dest[pos..], src[pos..]);
    }
}

fn fillPatternSimd(buffer: []u8, pattern: []const u8, features: simd_detector.CpuFeatures) void {
    const vector_size = features.getBestSimdLevel().getVectorSize();
    
    // Create pattern vector
    var pattern_vec: @Vector(vector_size, u8) = undefined;
    for (0..vector_size) |i| {
        pattern_vec[i] = pattern[i % pattern.len];
    }
    
    var pos: usize = 0;
    
    // Fill aligned chunks
    while (pos + vector_size <= buffer.len) {
        buffer[pos..][0..vector_size].* = pattern_vec;
        pos += vector_size;
    }
    
    // Fill remainder
    fillPatternScalar(buffer[pos..], pattern);
}

/// SIMD-accelerated JSON operations
pub const SimdJson = struct {
    /// Find next structural character ({}[],:") using SIMD
    pub fn findStructural(buffer: []const u8) ?usize {
        const features = simd_detector.detect();
        
        if (buffer.len >= 32 and features.getBestSimdLevel() != .none) {
            return findStructuralSimd(buffer, features);
        }
        
        return findStructuralScalar(buffer);
    }
    
    /// Validate string escapes using SIMD
    pub fn validateEscapes(str: []const u8) bool {
        const features = simd_detector.detect();
        
        if (str.len >= 32 and features.getBestSimdLevel() != .none) {
            return validateEscapesSimd(str, features);
        }
        
        return validateEscapesScalar(str);
    }
    
    /// Skip whitespace using SIMD
    pub fn skipWhitespace(buffer: []const u8) usize {
        const features = simd_detector.detect();
        
        if (buffer.len >= 32 and features.getBestSimdLevel() != .none) {
            return skipWhitespaceSimd(buffer, features);
        }
        
        return skipWhitespaceScalar(buffer);
    }
};

fn findStructuralScalar(buffer: []const u8) ?usize {
    for (buffer, 0..) |byte, i| {
        switch (byte) {
            '{', '}', '[', ']', ':', ',', '"' => return i,
            else => {},
        }
    }
    return null;
}

fn findStructuralSimd(buffer: []const u8, features: simd_detector.CpuFeatures) ?usize {
    const vector_size = features.getBestSimdLevel().getVectorSize();
    var pos: usize = 0;
    
    // Structural characters to find
    const chars = [_]u8{ '{', '}', '[', ']', ':', ',', '"' };
    
    while (pos + vector_size <= buffer.len) {
        const chunk: @Vector(vector_size, u8) = buffer[pos..][0..vector_size].*;
        
        // Check each structural character
        var any_match = @as(@Vector(vector_size, bool), @splat(false));
        inline for (chars) |char| {
            const char_vec = @as(@Vector(vector_size, u8), @splat(char));
            any_match = any_match | (chunk == char_vec);
        }
        
        if (@reduce(.Or, any_match)) {
            // Find first match
            for (0..vector_size) |i| {
                if (any_match[i]) {
                    return pos + i;
                }
            }
        }
        
        pos += vector_size;
    }
    
    // Check remainder
    if (findStructuralScalar(buffer[pos..])) |offset| {
        return pos + offset;
    }
    
    return null;
}

fn validateEscapesScalar(str: []const u8) bool {
    var i: usize = 0;
    while (i < str.len) {
        if (str[i] == '\\') {
            if (i + 1 >= str.len) return false;
            switch (str[i + 1]) {
                '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => i += 2,
                'u' => {
                    if (i + 5 >= str.len) return false;
                    // Validate hex digits
                    for (str[i + 2..i + 6]) |c| {
                        if (!std.ascii.isHex(c)) return false;
                    }
                    i += 6;
                },
                else => return false,
            }
        } else {
            i += 1;
        }
    }
    return true;
}

fn validateEscapesSimd(str: []const u8, features: simd_detector.CpuFeatures) bool {
    _ = features;
    // TODO: Implement SIMD validation
    return validateEscapesScalar(str);
}

fn skipWhitespaceScalar(buffer: []const u8) usize {
    for (buffer, 0..) |byte, i| {
        switch (byte) {
            ' ', '\t', '\n', '\r' => continue,
            else => return i,
        }
    }
    return buffer.len;
}

fn skipWhitespaceSimd(buffer: []const u8, features: simd_detector.CpuFeatures) usize {
    const vector_size = features.getBestSimdLevel().getVectorSize();
    var pos: usize = 0;
    
    // Whitespace characters
    const space_vec = @as(@Vector(vector_size, u8), @splat(' '));
    const tab_vec = @as(@Vector(vector_size, u8), @splat('\t'));
    const newline_vec = @as(@Vector(vector_size, u8), @splat('\n'));
    const return_vec = @as(@Vector(vector_size, u8), @splat('\r'));
    
    while (pos + vector_size <= buffer.len) {
        const chunk: @Vector(vector_size, u8) = buffer[pos..][0..vector_size].*;
        
        // Check if all bytes are whitespace
        const is_space = chunk == space_vec;
        const is_tab = chunk == tab_vec;
        const is_newline = chunk == newline_vec;
        const is_return = chunk == return_vec;
        
        const is_whitespace = is_space | is_tab | is_newline | is_return;
        
        if (!@reduce(.And, is_whitespace)) {
            // Found non-whitespace, find exact position
            for (0..vector_size) |i| {
                if (!is_whitespace[i]) {
                    return pos + i;
                }
            }
        }
        
        pos += vector_size;
    }
    
    // Check remainder
    return pos + skipWhitespaceScalar(buffer[pos..]);
}

// Tests
test "SIMD findByte" {
    const data = "Hello, World! This is a test string for SIMD operations.";
    
    const pos = SimdOps.findByte(data, '!');
    try std.testing.expect(pos != null);
    try std.testing.expectEqual(@as(usize, 12), pos.?);
    
    const not_found = SimdOps.findByte(data, 'z');
    try std.testing.expect(not_found == null);
}

test "SIMD countByte" {
    const data = "aaabbbcccdddeee";
    
    const count_a = SimdOps.countByte(data, 'a');
    try std.testing.expectEqual(@as(usize, 3), count_a);
    
    const count_e = SimdOps.countByte(data, 'e');
    try std.testing.expectEqual(@as(usize, 3), count_e);
}

test "SIMD allBytesEqual" {
    const all_zeros = [_]u8{0} ** 64;
    try std.testing.expect(SimdOps.allBytesEqual(&all_zeros, 0));
    
    var mixed = [_]u8{0} ** 64;
    mixed[32] = 1;
    try std.testing.expect(!SimdOps.allBytesEqual(&mixed, 0));
}

test "SIMD JSON operations" {
    const json = "   {\"key\": \"value\"}";
    
    const skip = SimdJson.skipWhitespace(json);
    try std.testing.expectEqual(@as(usize, 3), skip);
    
    const structural = SimdJson.findStructural(json[skip..]);
    try std.testing.expect(structural != null);
    try std.testing.expectEqual(@as(usize, 0), structural.?); // Found '{'
}