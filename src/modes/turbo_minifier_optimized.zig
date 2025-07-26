// TURBO Mode Optimized - Focus on key performance improvements
// Target: 2-3 GB/s throughput

const std = @import("std");
const builtin = @import("builtin");
const cpu_detection = @import("cpu_detection");

pub const TurboMinifierOptimized = struct {
    allocator: std.mem.Allocator,
    simd_strategy: cpu_detection.SimdStrategy,
    
    pub fn init(allocator: std.mem.Allocator) TurboMinifierOptimized {
        return .{
            .allocator = allocator,
            .simd_strategy = cpu_detection.getOptimalSimdStrategy(),
        };
    }
    
    pub fn minify(self: *TurboMinifierOptimized, input: []const u8, output: []u8) !usize {
        return switch (self.simd_strategy) {
            .avx512 => self.minifyAvx2(input, output), // Use AVX2 for now
            .avx2 => self.minifyAvx2(input, output),
            .sse2 => self.minifyAvx2(input, output), // Use AVX2 path for all SIMD
            .scalar => self.minifyScalar(input, output),
        };
    }
    
    // Optimized AVX2 implementation based on working turbo_minifier.zig
    fn minifyAvx2(self: *TurboMinifierOptimized, input: []const u8, output: []u8) !usize {
        _ = self;
        const vector_size = 32;
        const Vector = @Vector(vector_size, u8);
        
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        // Pre-computed vectors for structural characters
        const quote_vec = @as(Vector, @splat(@as(u8, '"')));
        const space_vec = @as(Vector, @splat(@as(u8, ' ')));
        const tab_vec = @as(Vector, @splat(@as(u8, '\t')));
        const newline_vec = @as(Vector, @splat(@as(u8, '\n')));
        const return_vec = @as(Vector, @splat(@as(u8, '\r')));
        
        // Process chunks with unaligned loads (fast on modern CPUs)
        while (i + vector_size <= input.len) {
            if (!in_string) {
                // Load chunk (unaligned access acceptable for performance)
                const chunk: Vector = @bitCast(input[i..i+vector_size][0..vector_size].*);
                
                // Find quotes and whitespace using SIMD comparison
                const quote_mask = chunk == quote_vec;
                const space_mask = chunk == space_vec;
                const tab_mask = chunk == tab_vec;
                const newline_mask = chunk == newline_vec;
                const return_mask = chunk == return_vec;
                
                // Combine whitespace masks
                var whitespace_mask: @Vector(vector_size, bool) = undefined;
                for (0..vector_size) |k| {
                    whitespace_mask[k] = space_mask[k] or tab_mask[k] or newline_mask[k] or return_mask[k];
                }
                
                if (@reduce(.Or, quote_mask)) {
                    // Found quote - process byte by byte until after quote
                    while (i < input.len) {
                        const c = input[i];
                        if (!isWhitespace(c)) {
                            output[out_pos] = c;
                            out_pos += 1;
                        }
                        i += 1;
                        if (c == '"') {
                            in_string = true;
                            break;
                        }
                    }
                } else {
                    // No quotes - filter whitespace efficiently
                    if (@reduce(.Or, whitespace_mask)) {
                        // Has whitespace - copy non-whitespace characters
                        for (0..vector_size) |j| {
                            if (!whitespace_mask[j]) {
                                output[out_pos] = chunk[j];
                                out_pos += 1;
                            }
                        }
                    } else {
                        // No whitespace - bulk copy entire chunk
                        @memcpy(output[out_pos..out_pos+vector_size], input[i..i+vector_size]);
                        out_pos += vector_size;
                    }
                    i += vector_size;
                }
            } else {
                // In string - copy everything until closing quote
                while (i < input.len) {
                    const c = input[i];
                    output[out_pos] = c;
                    out_pos += 1;
                    i += 1;
                    
                    if (escaped) {
                        escaped = false;
                    } else if (c == '\\') {
                        escaped = true;
                    } else if (c == '"') {
                        in_string = false;
                        break;
                    }
                }
            }
        }
        
        // Process remaining bytes
        while (i < input.len) {
            const c = input[i];
            
            if (escaped) {
                output[out_pos] = c;
                out_pos += 1;
                escaped = false;
            } else if (in_string) {
                output[out_pos] = c;
                out_pos += 1;
                if (c == '\\') {
                    escaped = true;
                } else if (c == '"') {
                    in_string = false;
                }
            } else {
                if (c == '"') {
                    output[out_pos] = c;
                    out_pos += 1;
                    in_string = true;
                } else if (!isWhitespace(c)) {
                    output[out_pos] = c;
                    out_pos += 1;
                }
            }
            i += 1;
        }
        
        return out_pos;
    }
    
    // Handle string content (including quotes)
    fn handleString(self: *TurboMinifierOptimized, input: []const u8, output: []u8) struct { output_len: usize, consumed: usize } {
        _ = self;
        if (input.len == 0 or input[0] != '"') {
            return .{ .output_len = 0, .consumed = 0 };
        }
        
        output[0] = '"';
        var i: usize = 1;
        var out: usize = 1;
        var escaped = false;
        
        while (i < input.len) : (i += 1) {
            output[out] = input[i];
            out += 1;
            
            if (escaped) {
                escaped = false;
            } else if (input[i] == '\\') {
                escaped = true;
            } else if (input[i] == '"') {
                return .{ .output_len = out, .consumed = i + 1 };
            }
        }
        
        return .{ .output_len = out, .consumed = i };
    }
    
    // Scalar fallback
    fn minifyScalar(self: *TurboMinifierOptimized, input: []const u8, output: []u8) !usize {
        _ = self;
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        while (i < input.len) : (i += 1) {
            const c = input[i];
            
            if (escaped) {
                output[out_pos] = c;
                out_pos += 1;
                escaped = false;
            } else if (in_string) {
                output[out_pos] = c;
                out_pos += 1;
                if (c == '\\') {
                    escaped = true;
                } else if (c == '"') {
                    in_string = false;
                }
            } else {
                if (c == '"') {
                    output[out_pos] = c;
                    out_pos += 1;
                    in_string = true;
                } else if (!isWhitespace(c)) {
                    output[out_pos] = c;
                    out_pos += 1;
                }
            }
        }
        
        return out_pos;
    }
    
    inline fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }
};