// TURBO Mode with SIMD Whitespace Detection
// Target: 10-20% performance boost over scalar implementation
// Strategy: Use SIMD for whitespace detection in hot paths, scalar for complex logic

const std = @import("std");
const builtin = @import("builtin");
const simd_utils = @import("../minifier/simd_utils.zig");

pub const TurboMinifierSimd = struct {
    allocator: std.mem.Allocator,
    
    // SIMD vector size based on architecture
    const vector_size = if (builtin.cpu.arch == .x86_64) 32 else 16;
    const VectorType = @Vector(vector_size, u8);
    
    pub fn init(allocator: std.mem.Allocator) TurboMinifierSimd {
        return .{
            .allocator = allocator,
        };
    }
    
    pub fn minify(self: *TurboMinifierSimd, input: []const u8, output: []u8) !usize {
        _ = self;
        
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        while (i < input.len) {
            if (in_string) {
                // In string: use bulk copying for efficiency
                const result = processStringWithSimd(input, output, i, out_pos);
                i = result.next_pos;
                out_pos = result.out_pos;
                in_string = result.in_string;
                escaped = result.escaped;
            } else {
                // Outside string: use SIMD for whitespace detection
                if (i + vector_size <= input.len) {
                    // Process full vector
                    const result = processVectorOutsideString(input, output, i, out_pos);
                    if (result.found_quote) {
                        // Found quote, switch to string mode
                        output[out_pos] = '"';
                        out_pos += 1;
                        in_string = true;
                        i = result.quote_pos + 1;
                    } else {
                        // No quote found, continue with next vector
                        out_pos = result.out_pos;
                        i += vector_size;
                    }
                } else {
                    // Less than vector_size bytes remaining - scalar processing
                    const c = input[i];
                    if (c == '"') {
                        output[out_pos] = c;
                        out_pos += 1;
                        in_string = true;
                    } else if (!isWhitespace(c)) {
                        output[out_pos] = c;
                        out_pos += 1;
                    }
                    i += 1;
                }
            }
        }
        
        return out_pos;
    }
    
    const VectorResult = struct {
        out_pos: usize,
        found_quote: bool,
        quote_pos: usize,
    };
    
    // SIMD processing for content outside strings
    fn processVectorOutsideString(input: []const u8, output: []u8, offset: usize, out_start: usize) VectorResult {
        const chunk = input[offset..][0..vector_size];
        const vec: VectorType = chunk.*;
        
        // Create comparison vectors
        const space_vec = @as(VectorType, @splat(' '));
        const tab_vec = @as(VectorType, @splat('\t'));
        const newline_vec = @as(VectorType, @splat('\n'));
        const cr_vec = @as(VectorType, @splat('\r'));
        const quote_vec = @as(VectorType, @splat('"'));
        
        var out_pos = out_start;
        
        // Check for quotes and process characters
        var quote_pos: usize = vector_size;
        for (0..vector_size) |j| {
            const c = vec[j];
            
            // Check for quote
            if (c == '"') {
                quote_pos = j;
                break;
            }
            
            // Check if it's whitespace using SIMD comparison results
            const is_space = (vec[j] == space_vec[j]);
            const is_tab = (vec[j] == tab_vec[j]);
            const is_newline = (vec[j] == newline_vec[j]);
            const is_cr = (vec[j] == cr_vec[j]);
            
            if (!is_space and !is_tab and !is_newline and !is_cr) {
                output[out_pos] = c;
                out_pos += 1;
            }
        }
        
        return VectorResult{
            .out_pos = out_pos,
            .found_quote = quote_pos < vector_size,
            .quote_pos = offset + quote_pos,
        };
    }
    
    const StringResult = struct {
        next_pos: usize,
        out_pos: usize,
        in_string: bool,
        escaped: bool,
    };
    
    // Process string content with SIMD acceleration
    fn processStringWithSimd(input: []const u8, output: []u8, start_pos: usize, out_start: usize) StringResult {
        var pos = start_pos;
        var out_pos = out_start;
        var escaped = false;
        
        // Process in vector-sized chunks when possible
        while (pos + vector_size <= input.len) {
            const chunk = input[pos..][0..vector_size];
            const vec: VectorType = chunk.*;
            
            // Look for quotes and backslashes
            const quote_vec = @as(VectorType, @splat('"'));
            const backslash_vec = @as(VectorType, @splat('\\'));
            
            const quote_mask = vec == quote_vec;
            const backslash_mask = vec == backslash_vec;
            
            // Find first special character
            var special_pos: usize = vector_size;
            for (0..vector_size) |j| {
                if (!escaped and (quote_mask[j] or backslash_mask[j])) {
                    special_pos = j;
                    break;
                }
            }
            
            // Bulk copy up to special character
            if (special_pos > 0) {
                @memcpy(output[out_pos..out_pos + special_pos], chunk[0..special_pos]);
                out_pos += special_pos;
                pos += special_pos;
            }
            
            // Handle special character if found
            if (special_pos < vector_size) {
                const c = chunk[special_pos];
                if (c == '"' and !escaped) {
                    // End of string
                    output[out_pos] = '"';
                    out_pos += 1;
                    return StringResult{
                        .next_pos = pos + 1,
                        .out_pos = out_pos,
                        .in_string = false,
                        .escaped = false,
                    };
                } else if (c == '\\' and !escaped) {
                    escaped = true;
                    output[out_pos] = c;
                    out_pos += 1;
                    pos += 1;
                } else {
                    escaped = false;
                    output[out_pos] = c;
                    out_pos += 1;
                    pos += 1;
                }
            } else {
                // No special characters in this vector
                pos += vector_size;
            }
        }
        
        // Handle remaining bytes with scalar processing
        while (pos < input.len) {
            const c = input[pos];
            output[out_pos] = c;
            out_pos += 1;
            
            if (c == '"' and !escaped) {
                return StringResult{
                    .next_pos = pos + 1,
                    .out_pos = out_pos,
                    .in_string = false,
                    .escaped = false,
                };
            } else if (c == '\\' and !escaped) {
                escaped = true;
            } else {
                escaped = false;
            }
            pos += 1;
        }
        
        return StringResult{
            .next_pos = pos,
            .out_pos = out_pos,
            .in_string = true,
            .escaped = escaped,
        };
    }
    
    // Scalar whitespace detection for edge cases
    inline fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }
};