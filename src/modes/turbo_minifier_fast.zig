// TURBO Mode FAST - Aggressive optimization for 2-3 GB/s
// Key insights from profiling:
// 1. String processing is fast - don't over-optimize it
// 2. Alignment checks are expensive - minimize them
// 3. Quote detection causes too many fallbacks

const std = @import("std");
const builtin = @import("builtin");
const cpu_detection = @import("cpu_detection");

pub const TurboMinifierFast = struct {
    allocator: std.mem.Allocator,
    simd_strategy: cpu_detection.SimdStrategy,
    
    pub fn init(allocator: std.mem.Allocator) TurboMinifierFast {
        return .{
            .allocator = allocator,
            .simd_strategy = cpu_detection.getOptimalSimdStrategy(),
        };
    }
    
    pub fn minify(self: *TurboMinifierFast, input: []const u8, output: []u8) !usize {
        // For now, always use the fast path
        return self.minifyFast(input, output);
    }
    
    // Fast implementation - minimize branches and checks
    fn minifyFast(self: *TurboMinifierFast, input: []const u8, output: []u8) !usize {
        
        var in_pos: usize = 0;
        var out_pos: usize = 0;
        
        // Process in larger chunks to amortize overhead
        const chunk_size = 256; // Process 256 bytes at a time
        
        while (in_pos + chunk_size <= input.len) {
            // Quick scan for quotes in the chunk
            var has_quote = false;
            var quote_pos: usize = chunk_size;
            
            // Unrolled loop for better performance
            var scan_pos: usize = 0;
            while (scan_pos + 8 <= chunk_size) : (scan_pos += 8) {
                if (input[in_pos + scan_pos] == '"' or
                    input[in_pos + scan_pos + 1] == '"' or
                    input[in_pos + scan_pos + 2] == '"' or
                    input[in_pos + scan_pos + 3] == '"' or
                    input[in_pos + scan_pos + 4] == '"' or
                    input[in_pos + scan_pos + 5] == '"' or
                    input[in_pos + scan_pos + 6] == '"' or
                    input[in_pos + scan_pos + 7] == '"') {
                    has_quote = true;
                    // Find exact position
                    for (scan_pos..scan_pos + 8) |i| {
                        if (input[in_pos + i] == '"') {
                            quote_pos = i;
                            break;
                        }
                    }
                    break;
                }
            }
            
            // Check remaining bytes if needed
            if (!has_quote) {
                while (scan_pos < chunk_size) : (scan_pos += 1) {
                    if (input[in_pos + scan_pos] == '"') {
                        has_quote = true;
                        quote_pos = scan_pos;
                        break;
                    }
                }
            }
            
            if (!has_quote) {
                // Fast path - no quotes in chunk, bulk process
                out_pos += self.processChunkNoQuotes(input[in_pos..in_pos + chunk_size], output[out_pos..]);
                in_pos += chunk_size;
            } else {
                // Process up to quote
                if (quote_pos > 0) {
                    out_pos += self.processChunkNoQuotes(input[in_pos..in_pos + quote_pos], output[out_pos..]);
                    in_pos += quote_pos;
                }
                
                // Handle string
                const string_len = self.findStringEnd(input[in_pos..]);
                @memcpy(output[out_pos..out_pos + string_len], input[in_pos..in_pos + string_len]);
                out_pos += string_len;
                in_pos += string_len;
            }
        }
        
        // Process remainder
        while (in_pos < input.len) {
            const c = input[in_pos];
            if (c == '"') {
                const string_len = self.findStringEnd(input[in_pos..]);
                @memcpy(output[out_pos..out_pos + string_len], input[in_pos..in_pos + string_len]);
                out_pos += string_len;
                in_pos += string_len;
            } else {
                if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                    output[out_pos] = c;
                    out_pos += 1;
                }
                in_pos += 1;
            }
        }
        
        return out_pos;
    }
    
    // Process chunk with no quotes - optimized for speed
    fn processChunkNoQuotes(self: *TurboMinifierFast, chunk: []const u8, output: []u8) usize {
        var out_idx: usize = 0;
        
        // Use SIMD if available and chunk is large enough
        if (chunk.len >= 32 and self.simd_strategy != .scalar) {
            return self.processChunkSIMD(chunk, output);
        }
        
        // Unrolled scalar loop
        var i: usize = 0;
        while (i + 8 <= chunk.len) : (i += 8) {
            // Process 8 bytes at a time
            inline for (0..8) |j| {
                const c = chunk[i + j];
                if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                    output[out_idx] = c;
                    out_idx += 1;
                }
            }
        }
        
        // Handle remainder
        while (i < chunk.len) : (i += 1) {
            const c = chunk[i];
            if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                output[out_idx] = c;
                out_idx += 1;
            }
        }
        
        return out_idx;
    }
    
    // SIMD version for chunks
    fn processChunkSIMD(self: *TurboMinifierFast, chunk: []const u8, output: []u8) usize {
        _ = self;
        const Vector32 = @Vector(32, u8);
        var out_idx: usize = 0;
        var i: usize = 0;
        
        // Create comparison vectors
        const space_vec = @as(Vector32, @splat(' '));
        const tab_vec = @as(Vector32, @splat('\t'));
        const newline_vec = @as(Vector32, @splat('\n'));
        const return_vec = @as(Vector32, @splat('\r'));
        
        // Process 32-byte aligned chunks
        while (i + 32 <= chunk.len) {
            var vec: Vector32 = undefined;
            
            // Load data (handle alignment)
            if (@intFromPtr(&chunk[i]) % @alignOf(Vector32) == 0) {
                vec = @as(*const Vector32, @ptrCast(@alignCast(&chunk[i]))).*;
            } else {
                // Unaligned load
                for (0..32) |j| {
                    vec[j] = chunk[i + j];
                }
            }
            
            // Check for whitespace
            const is_space = vec == space_vec;
            const is_tab = vec == tab_vec;
            const is_newline = vec == newline_vec;
            const is_return = vec == return_vec;
            
            // Process results
            for (0..32) |j| {
                if (!is_space[j] and !is_tab[j] and !is_newline[j] and !is_return[j]) {
                    output[out_idx] = vec[j];
                    out_idx += 1;
                }
            }
            
            i += 32;
        }
        
        // Handle remainder with scalar code
        while (i < chunk.len) : (i += 1) {
            const c = chunk[i];
            if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                output[out_idx] = c;
                out_idx += 1;
            }
        }
        
        return out_idx;
    }
    
    // Find end of string - optimized
    fn findStringEnd(self: *TurboMinifierFast, input: []const u8) usize {
        _ = self;
        if (input.len == 0 or input[0] != '"') return 0;
        
        var i: usize = 1;
        var escaped = false;
        
        // Unroll the loop for better performance
        while (i + 4 <= input.len) {
            if (escaped) {
                escaped = false;
                i += 1;
                continue;
            }
            
            // Check 4 characters at once
            if (input[i] == '\\') {
                escaped = true;
                i += 1;
            } else if (input[i] == '"') {
                return i + 1;
            } else if (input[i + 1] == '"') {
                return i + 2;
            } else if (input[i + 2] == '"') {
                return i + 3;
            } else if (input[i + 3] == '"') {
                return i + 4;
            } else {
                i += 4;
            }
        }
        
        // Handle remainder
        while (i < input.len) : (i += 1) {
            if (escaped) {
                escaped = false;
            } else if (input[i] == '\\') {
                escaped = true;
            } else if (input[i] == '"') {
                return i + 1;
            }
        }
        
        return input.len;
    }
};