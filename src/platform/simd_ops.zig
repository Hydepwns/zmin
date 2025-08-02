//! SIMD Operations Abstraction Layer
//! 
//! This module provides a unified interface for SIMD operations across
//! different architectures, abstracting the complexity of platform-specific
//! optimizations while maintaining maximum performance.
//!
//! Supported Operations:
//! - Whitespace removal (primary JSON minification operation)
//! - Character classification and vectorized searches
//! - Memory operations with SIMD acceleration
//! - String processing with escape detection

const std = @import("std");
const builtin = @import("builtin");
const arch_detector = @import("arch_detector.zig");

/// SIMD optimization levels
pub const SIMDLevel = enum {
    basic,    // Basic SIMD with conservative optimizations
    avx2,     // AVX2 optimizations
    avx512,   // AVX-512 optimizations  
    neon,     // ARM NEON optimizations
    adaptive, // Automatically choose best available
};

/// Minify JSON using SIMD optimizations
pub fn minifyWithSIMD(input: []const u8, output: []u8, level: SIMDLevel) !usize {
    const caps = arch_detector.detectCapabilities();
    
    const actual_level = if (level == .adaptive) 
        selectOptimalSIMDLevel(caps) 
    else 
        level;
    
    return switch (actual_level) {
        .avx512 => if (caps.has_avx512) minifyAVX512(input, output) else minifyAVX2(input, output),
        .avx2 => if (caps.has_avx2) minifyAVX2(input, output) else minifyBasic(input, output),
        .neon => if (caps.has_neon) minifyNEON(input, output) else minifyBasic(input, output),
        .basic => minifyBasic(input, output),
        .adaptive => unreachable, // Already resolved above
    };
}

/// Select optimal SIMD level based on hardware capabilities
fn selectOptimalSIMDLevel(caps: arch_detector.HardwareCapabilities) SIMDLevel {
    if (caps.has_avx512) return .avx512;
    if (caps.has_avx2) return .avx2;
    if (caps.has_neon) return .neon;
    return .basic;
}

/// Basic SIMD minification (SSE2/portable)
fn minifyBasic(input: []const u8, output: []u8) usize {
    var out_pos: usize = 0;
    var in_string = false;
    var escape_next = false;
    
    // Process data in chunks where possible
    var pos: usize = 0;
    
    // Process 16-byte chunks when not in string and no escapes
    while (pos + 16 <= input.len and !in_string and !escape_next) {
        const chunk = input[pos..pos + 16];
        
        // Check if chunk contains quotes or escapes
        var has_special = false;
        for (chunk) |byte| {
            if (byte == '"' or byte == '\\') {
                has_special = true;
                break;
            }
        }
        
        if (!has_special) {
            // Fast path: remove whitespace from chunk
            for (chunk) |byte| {
                if (byte != ' ' and byte != '\t' and byte != '\n' and byte != '\r') {
                    output[out_pos] = byte;
                    out_pos += 1;
                }
            }
            pos += 16;
        } else {
            // Fall back to byte-by-byte processing
            break;
        }
    }
    
    // Process remaining bytes byte-by-byte
    while (pos < input.len) {
        const byte = input[pos];
        
        if (escape_next) {
            output[out_pos] = byte;
            out_pos += 1;
            escape_next = false;
        } else {
            switch (byte) {
                '"' => {
                    in_string = !in_string;
                    output[out_pos] = byte;
                    out_pos += 1;
                },
                '\\' => {
                    if (in_string) escape_next = true;
                    output[out_pos] = byte;
                    out_pos += 1;
                },
                ' ', '\t', '\n', '\r' => {
                    if (in_string) {
                        output[out_pos] = byte;
                        out_pos += 1;
                    }
                    // Skip whitespace outside strings
                },
                else => {
                    output[out_pos] = byte;
                    out_pos += 1;
                },
            }
        }
        
        pos += 1;
    }
    
    return out_pos;
}

/// AVX2 optimized minification (32-byte vectors)
fn minifyAVX2(input: []const u8, output: []u8) usize {
    if (builtin.cpu.arch != .x86_64) {
        return minifyBasic(input, output);
    }
    
    var out_pos: usize = 0;
    var pos: usize = 0;
    var in_string = false;
    
    // Process 32-byte chunks with AVX2
    while (pos + 32 <= input.len and !in_string) {
        const chunk = input[pos..pos + 32];
        
        // Load 32 bytes into AVX2 register (simulated)
        const input_vec = @as(@Vector(32, u8), chunk[0..32].*);
        
        // Create comparison vectors for whitespace
        const space_vec: @Vector(32, u8) = @splat(' ');
        const tab_vec: @Vector(32, u8) = @splat('\t');
        const newline_vec: @Vector(32, u8) = @splat('\n');
        const cr_vec: @Vector(32, u8) = @splat('\r');
        const quote_vec: @Vector(32, u8) = @splat('"');
        const escape_vec: @Vector(32, u8) = @splat('\\');
        
        // Find whitespace and special characters
        const space_mask = input_vec == space_vec;
        const tab_mask = input_vec == tab_vec;
        const newline_mask = input_vec == newline_vec;
        const cr_mask = input_vec == cr_vec;
        const quote_mask = input_vec == quote_vec;
        const escape_mask = input_vec == escape_vec;
        
        const whitespace_mask = (space_mask or tab_mask) or (newline_mask or cr_mask);
        const special_mask = quote_mask or escape_mask;
        
        // Check if we have special characters that need careful handling
        const special_bits = @as(u32, @bitCast(special_mask));
        if (special_bits != 0) {
            // Fall back to scalar processing for this chunk
            break;
        }
        
        // Remove whitespace using vector operations
        const keep_mask = ~whitespace_mask;
        
        // Compact non-whitespace characters
        var chunk_out_pos: usize = 0;
        for (chunk, 0..) |byte, i| {
            if (keep_mask[i]) {
                output[out_pos + chunk_out_pos] = byte;
                chunk_out_pos += 1;
            }
        }
        
        out_pos += chunk_out_pos;
        pos += 32;
    }
    
    // Process remaining bytes with scalar algorithm
    while (pos < input.len) {
        const byte = input[pos];
        
        switch (byte) {
            '"' => {
                in_string = !in_string;
                output[out_pos] = byte;
                out_pos += 1;
            },
            ' ', '\t', '\n', '\r' => {
                if (in_string) {
                    output[out_pos] = byte;
                    out_pos += 1;
                }
            },
            else => {
                output[out_pos] = byte;
                out_pos += 1;
            },
        }
        
        pos += 1;
    }
    
    return out_pos;
}

/// AVX-512 optimized minification (64-byte vectors)
fn minifyAVX512(input: []const u8, output: []u8) usize {
    if (builtin.cpu.arch != .x86_64) {
        return minifyAVX2(input, output);
    }
    
    var out_pos: usize = 0;
    var pos: usize = 0;
    var in_string = false;
    
    // Process 64-byte chunks with AVX-512
    while (pos + 64 <= input.len and !in_string) {
        const chunk = input[pos..pos + 64];
        
        // Load 64 bytes into AVX-512 register (simulated)
        const input_vec = @as(@Vector(64, u8), chunk[0..64].*);
        
        // Create comparison vectors
        const space_vec: @Vector(64, u8) = @splat(' ');
        const tab_vec: @Vector(64, u8) = @splat('\t');
        const newline_vec: @Vector(64, u8) = @splat('\n');
        const cr_vec: @Vector(64, u8) = @splat('\r');
        const quote_vec: @Vector(64, u8) = @splat('"');
        const escape_vec: @Vector(64, u8) = @splat('\\');
        
        // Find characters
        const space_mask = input_vec == space_vec;
        const tab_mask = input_vec == tab_vec;
        const newline_mask = input_vec == newline_vec;
        const cr_mask = input_vec == cr_vec;
        const quote_mask = input_vec == quote_vec;
        const escape_mask = input_vec == escape_vec;
        
        const whitespace_mask = (space_mask or tab_mask) or (newline_mask or cr_mask);
        const special_mask = quote_mask or escape_mask;
        
        // Check for special characters
        const special_bits = @as(u64, @bitCast(special_mask));
        if (special_bits != 0) {
            // Handle special characters in scalar mode
            break;
        }
        
        // Use AVX-512 VPCOMPRESSB-like operation (simulated)
        const keep_mask = ~whitespace_mask;
        
        // Compress non-whitespace characters
        var chunk_out_pos: usize = 0;
        for (chunk, 0..) |byte, i| {
            if (keep_mask[i]) {
                output[out_pos + chunk_out_pos] = byte;
                chunk_out_pos += 1;
            }
        }
        
        out_pos += chunk_out_pos;
        pos += 64;
    }
    
    // Process remaining bytes
    while (pos < input.len) {
        const byte = input[pos];
        
        switch (byte) {
            '"' => {
                in_string = !in_string;
                output[out_pos] = byte;
                out_pos += 1;
            },
            ' ', '\t', '\n', '\r' => {
                if (in_string) {
                    output[out_pos] = byte;
                    out_pos += 1;
                }
            },
            else => {
                output[out_pos] = byte;
                out_pos += 1;
            },
        }
        
        pos += 1;
    }
    
    return out_pos;
}

/// ARM NEON optimized minification (16-byte vectors)
fn minifyNEON(input: []const u8, output: []u8) usize {
    if (builtin.cpu.arch != .aarch64) {
        return minifyBasic(input, output);
    }
    
    var out_pos: usize = 0;
    var pos: usize = 0;
    var in_string = false;
    
    // Process 16-byte chunks with NEON
    while (pos + 16 <= input.len and !in_string) {
        const chunk = input[pos..pos + 16];
        
        // Load 16 bytes into NEON register (simulated)
        const input_vec = @as(@Vector(16, u8), chunk[0..16].*);
        
        // Create comparison vectors for NEON
        const space_vec: @Vector(16, u8) = @splat(' ');
        const tab_vec: @Vector(16, u8) = @splat('\t');
        const newline_vec: @Vector(16, u8) = @splat('\n');
        const cr_vec: @Vector(16, u8) = @splat('\r');
        const quote_vec: @Vector(16, u8) = @splat('"');
        const escape_vec: @Vector(16, u8) = @splat('\\');
        
        // NEON comparisons
        const space_mask = input_vec == space_vec;
        const tab_mask = input_vec == tab_vec;
        const newline_mask = input_vec == newline_vec;
        const cr_mask = input_vec == cr_vec;
        const quote_mask = input_vec == quote_vec;
        const escape_mask = input_vec == escape_vec;
        
        const whitespace_mask = (space_mask or tab_mask) or (newline_mask or cr_mask);
        const special_mask = quote_mask or escape_mask;
        
        // Check for special characters
        const special_bits = @as(u16, @bitCast(special_mask));
        if (special_bits != 0) {
            break; // Fall back to scalar
        }
        
        // Use NEON table lookup for compression (simulated)
        const keep_mask = ~whitespace_mask;
        
        var chunk_out_pos: usize = 0;
        for (chunk, 0..) |byte, i| {
            if (keep_mask[i]) {
                output[out_pos + chunk_out_pos] = byte;
                chunk_out_pos += 1;
            }
        }
        
        out_pos += chunk_out_pos;
        pos += 16;
    }
    
    // Process remaining bytes
    while (pos < input.len) {
        const byte = input[pos];
        
        switch (byte) {
            '"' => {
                in_string = !in_string;
                output[out_pos] = byte;
                out_pos += 1;
            },
            ' ', '\t', '\n', '\r' => {
                if (in_string) {
                    output[out_pos] = byte;
                    out_pos += 1;
                }
            },
            else => {
                output[out_pos] = byte;
                out_pos += 1;
            },
        }
        
        pos += 1;
    }
    
    return out_pos;
}

/// Vectorized character search
pub fn findCharacterSIMD(haystack: []const u8, needle: u8, level: SIMDLevel) ?usize {
    const caps = arch_detector.detectCapabilities();
    
    return switch (level) {
        .avx512 => if (caps.has_avx512) findCharacterAVX512(haystack, needle) else findCharacterAVX2(haystack, needle),
        .avx2 => if (caps.has_avx2) findCharacterAVX2(haystack, needle) else findCharacterBasic(haystack, needle),
        .neon => if (caps.has_neon) findCharacterNEON(haystack, needle) else findCharacterBasic(haystack, needle),
        .basic => findCharacterBasic(haystack, needle),
        .adaptive => findCharacterSIMD(haystack, needle, selectOptimalSIMDLevel(caps)),
    };
}

fn findCharacterBasic(haystack: []const u8, needle: u8) ?usize {
    for (haystack, 0..) |byte, i| {
        if (byte == needle) return i;
    }
    return null;
}

fn findCharacterAVX2(haystack: []const u8, needle: u8) ?usize {
    var pos: usize = 0;
    
    // Process 32-byte chunks
    while (pos + 32 <= haystack.len) {
        const chunk = haystack[pos..pos + 32];
        const input_vec = @as(@Vector(32, u8), chunk[0..32].*);
        const needle_vec: @Vector(32, u8) = @splat(needle);
        
        const match_mask = input_vec == needle_vec;
        const match_bits = @as(u32, @bitCast(match_mask));
        
        if (match_bits != 0) {
            const first_match = @ctz(match_bits);
            return pos + first_match;
        }
        
        pos += 32;
    }
    
    // Check remaining bytes
    return findCharacterBasic(haystack[pos..], needle);
}

fn findCharacterAVX512(haystack: []const u8, needle: u8) ?usize {
    var pos: usize = 0;
    
    // Process 64-byte chunks
    while (pos + 64 <= haystack.len) {
        const chunk = haystack[pos..pos + 64];
        const input_vec = @as(@Vector(64, u8), chunk[0..64].*);
        const needle_vec: @Vector(64, u8) = @splat(needle);
        
        const match_mask = input_vec == needle_vec;
        const match_bits = @as(u64, @bitCast(match_mask));
        
        if (match_bits != 0) {
            const first_match = @ctz(match_bits);
            return pos + first_match;
        }
        
        pos += 64;
    }
    
    // Check remaining bytes
    return findCharacterBasic(haystack[pos..], needle);
}

fn findCharacterNEON(haystack: []const u8, needle: u8) ?usize {
    var pos: usize = 0;
    
    // Process 16-byte chunks
    while (pos + 16 <= haystack.len) {
        const chunk = haystack[pos..pos + 16];
        const input_vec = @as(@Vector(16, u8), chunk[0..16].*);
        const needle_vec: @Vector(16, u8) = @splat(needle);
        
        const match_mask = input_vec == needle_vec;
        const match_bits = @as(u16, @bitCast(match_mask));
        
        if (match_bits != 0) {
            const first_match = @ctz(match_bits);
            return pos + first_match;
        }
        
        pos += 16;
    }
    
    // Check remaining bytes
    return findCharacterBasic(haystack[pos..], needle);
}

/// Vectorized memory copy with prefetching
pub fn memcpySIMD(dest: []u8, src: []const u8, level: SIMDLevel) void {
    if (dest.len != src.len) {
        @memcpy(dest, src);
        return;
    }
    
    const caps = arch_detector.detectCapabilities();
    const actual_level = if (level == .adaptive) selectOptimalSIMDLevel(caps) else level;
    
    switch (actual_level) {
        .avx512 => if (caps.has_avx512) memcpyAVX512(dest, src) else memcpyAVX2(dest, src),
        .avx2 => if (caps.has_avx2) memcpyAVX2(dest, src) else @memcpy(dest, src),
        .neon => if (caps.has_neon) memcpyNEON(dest, src) else @memcpy(dest, src),
        .basic => @memcpy(dest, src),
        .adaptive => unreachable,
    }
}

fn memcpyAVX512(dest: []u8, src: []const u8) void {
    var pos: usize = 0;
    
    // Copy 64-byte chunks
    while (pos + 64 <= src.len) {
        const src_chunk = src[pos..pos + 64];
        const src_vec = @as(@Vector(64, u8), src_chunk[0..64].*);
        const dest_chunk: [64]u8 = src_vec;
        @memcpy(dest[pos..pos + 64], &dest_chunk);
        pos += 64;
    }
    
    // Copy remaining bytes
    if (pos < src.len) {
        @memcpy(dest[pos..], src[pos..]);
    }
}

fn memcpyAVX2(dest: []u8, src: []const u8) void {
    var pos: usize = 0;
    
    // Copy 32-byte chunks
    while (pos + 32 <= src.len) {
        const src_chunk = src[pos..pos + 32];
        const src_vec = @as(@Vector(32, u8), src_chunk[0..32].*);
        const dest_chunk: [32]u8 = src_vec;
        @memcpy(dest[pos..pos + 32], &dest_chunk);
        pos += 32;
    }
    
    // Copy remaining bytes
    if (pos < src.len) {
        @memcpy(dest[pos..], src[pos..]);
    }
}

fn memcpyNEON(dest: []u8, src: []const u8) void {
    var pos: usize = 0;
    
    // Copy 16-byte chunks
    while (pos + 16 <= src.len) {
        const src_chunk = src[pos..pos + 16];
        const src_vec = @as(@Vector(16, u8), src_chunk[0..16].*);
        const dest_chunk: [16]u8 = src_vec;
        @memcpy(dest[pos..pos + 16], &dest_chunk);
        pos += 16;
    }
    
    // Copy remaining bytes
    if (pos < src.len) {
        @memcpy(dest[pos..], src[pos..]);
    }
}

/// Benchmark SIMD operations
pub fn benchmarkSIMDOperations(allocator: std.mem.Allocator) !void {
    const test_size = 1024 * 1024; // 1MB
    const input = try allocator.alloc(u8, test_size);
    const output = try allocator.alloc(u8, test_size);
    defer allocator.free(input);
    defer allocator.free(output);
    
    // Fill with test data
    for (input, 0..) |*byte, i| {
        switch (i % 8) {
            0, 1, 2 => byte.* = ' ',  // 37.5% whitespace
            3 => byte.* = '\t',
            4 => byte.* = '"',
            5 => byte.* = '{',
            6 => byte.* = '}',
            7 => byte.* = 'a' + @as(u8, @intCast(i % 26)),
        }
    }
    
    const levels = [_]SIMDLevel{ .basic, .avx2, .avx512, .neon };
    
    for (levels) |level| {
        const caps = arch_detector.detectCapabilities();
        if (!isSIMDLevelSupported(level, caps)) continue;
        
        const iterations = 1000;
        const start_time = std.time.nanoTimestamp();
        
        for (0..iterations) |_| {
            const result_size = minifyWithSIMD(input, output, level) catch continue;
            _ = result_size;
        }
        
        const end_time = std.time.nanoTimestamp();
        const duration_ns = @as(u64, @intCast(end_time - start_time));
        const throughput_bps = (@as(f64, @floatFromInt(test_size * iterations)) * 1_000_000_000.0) / @as(f64, @floatFromInt(duration_ns));
        const throughput_gbps = throughput_bps / (1024.0 * 1024.0 * 1024.0);
        
        std.debug.print("SIMD Level {}: {d:.2} GB/s\n", .{ level, throughput_gbps });
    }
}

fn isSIMDLevelSupported(level: SIMDLevel, caps: arch_detector.HardwareCapabilities) bool {
    return switch (level) {
        .basic => true,
        .avx2 => caps.has_avx2,
        .avx512 => caps.has_avx512,
        .neon => caps.has_neon,
        .adaptive => true,
    };
}