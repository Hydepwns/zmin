// Advanced SIMD JSON minifier using AVX2/AVX-512 when available
const std = @import("std");
const CPUFeatures = @import("cpu_features.zig").CPUFeatures;

pub const AdvancedSIMDMinifier = struct {
    allocator: std.mem.Allocator,
    cpu_features: CPUFeatures,
    simd_level: CPUFeatures.SIMDLevel,
    
    pub fn init(allocator: std.mem.Allocator) !AdvancedSIMDMinifier {
        const cpu_features = CPUFeatures.detect();
        const simd_level = cpu_features.getBestSIMDLevel();
        
        return AdvancedSIMDMinifier{
            .allocator = allocator,
            .cpu_features = cpu_features,
            .simd_level = simd_level,
        };
    }
    
    pub fn deinit(self: *AdvancedSIMDMinifier) void {
        _ = self;
    }
    
    pub fn minify(self: *AdvancedSIMDMinifier, input: []const u8, output: []u8) !usize {
        // Select optimal implementation based on available SIMD
        return switch (self.simd_level) {
            .avx512 => self.minifyAVX512(input, output),
            .avx2 => self.minifyAVX2(input, output),
            .avx => self.minifyAVX(input, output),
            .sse4_1 => self.minifySSE41(input, output),
            .sse2 => self.minifySSE2(input, output),
            .scalar => self.minifyScalar(input, output),
        };
    }
    
    // AVX-512 implementation (64-byte vectors)
    fn minifyAVX512(self: *AdvancedSIMDMinifier, input: []const u8, output: []u8) !usize {
        _ = self;
        
        // For systems with AVX-512, process 64 bytes at a time
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        const vector_size = 64;
        _ = self; // May be used for future optimizations
        
        // Process in 64-byte chunks when not in string
        while (i + vector_size <= input.len and !in_string) {
            const chunk = @as(@Vector(64, u8), input[i..i + vector_size][0..vector_size].*);
            
            // Check for quotes in chunk
            const quote_mask = chunk == @as(@Vector(64, u8), @splat('"'));
            const has_quotes = @reduce(.Or, quote_mask);
            
            if (has_quotes) {
                // Fall back to scalar processing for string handling
                break;
            }
            
            // Vectorized whitespace detection
            const is_space = chunk == @as(@Vector(64, u8), @splat(' '));
            const is_tab = chunk == @as(@Vector(64, u8), @splat('\t'));
            const is_newline = chunk == @as(@Vector(64, u8), @splat('\n'));
            const is_cr = chunk == @as(@Vector(64, u8), @splat('\r'));
            const is_whitespace = @select(bool, is_space, @as(@Vector(64, bool), @splat(true)), @select(bool, is_tab, @as(@Vector(64, bool), @splat(true)), @select(bool, is_newline, @as(@Vector(64, bool), @splat(true)), @select(bool, is_cr, @as(@Vector(64, bool), @splat(true)), @as(@Vector(64, bool), @splat(false))))));
            
            // Copy non-whitespace characters
            for (0..vector_size) |j| {
                if (!is_whitespace[j]) {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = chunk[j];
                    out_pos += 1;
                }
            }
            
            i += vector_size;
        }
        
        // Process remaining bytes with scalar method
        while (i < input.len) {
            const c = input[i];
            
            if (in_string) {
                if (out_pos >= output.len) return error.OutputBufferTooSmall;
                output[out_pos] = c;
                out_pos += 1;
                
                if (c == '\\' and !escaped) {
                    escaped = true;
                } else if (c == '"' and !escaped) {
                    in_string = false;
                    escaped = false;
                } else {
                    escaped = false;
                }
            } else {
                if (c == '"') {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                    in_string = true;
                } else if (!isWhitespace(c)) {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                }
            }
            
            i += 1;
        }
        
        return out_pos;
    }
    
    // AVX2 implementation (32-byte vectors)
    fn minifyAVX2(self: *AdvancedSIMDMinifier, input: []const u8, output: []u8) !usize {
        _ = self;
        
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        const vector_size = 32;
        
        // Process in 32-byte chunks when not in string
        while (i + vector_size <= input.len and !in_string) {
            const chunk = @as(@Vector(32, u8), input[i..i + vector_size][0..vector_size].*);
            
            // Check for quotes in chunk
            const quote_mask = chunk == @as(@Vector(32, u8), @splat('"'));
            const has_quotes = @reduce(.Or, quote_mask);
            
            if (has_quotes) {
                break; // Fall back to scalar processing
            }
            
            // Vectorized whitespace detection
            const is_space = chunk == @as(@Vector(32, u8), @splat(' '));
            const is_tab = chunk == @as(@Vector(32, u8), @splat('\t'));
            const is_newline = chunk == @as(@Vector(32, u8), @splat('\n'));
            const is_cr = chunk == @as(@Vector(32, u8), @splat('\r'));
            const is_whitespace = @select(bool, is_space, @as(@Vector(32, bool), @splat(true)), @select(bool, is_tab, @as(@Vector(32, bool), @splat(true)), @select(bool, is_newline, @as(@Vector(32, bool), @splat(true)), @select(bool, is_cr, @as(@Vector(32, bool), @splat(true)), @as(@Vector(32, bool), @splat(false))))));
            
            // Copy non-whitespace characters using bit manipulation
            comptime var j = 0;
            inline while (j < vector_size) : (j += 1) {
                if (!is_whitespace[j]) {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = chunk[j];
                    out_pos += 1;
                }
            }
            
            i += vector_size;
        }
        
        // Scalar processing for remaining bytes and string content
        while (i < input.len) {
            const c = input[i];
            
            if (in_string) {
                if (out_pos >= output.len) return error.OutputBufferTooSmall;
                output[out_pos] = c;
                out_pos += 1;
                
                if (c == '\\' and !escaped) {
                    escaped = true;
                } else if (c == '"' and !escaped) {
                    in_string = false;
                    escaped = false;
                } else {
                    escaped = false;
                }
            } else {
                if (c == '"') {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                    in_string = true;
                } else if (!isWhitespace(c)) {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                }
            }
            
            i += 1;
        }
        
        return out_pos;
    }
    
    // AVX implementation (32-byte vectors, older instruction set)
    fn minifyAVX(self: *AdvancedSIMDMinifier, input: []const u8, output: []u8) !usize {
        // Similar to AVX2 but with more conservative optimizations
        return self.minifyAVX2(input, output);
    }
    
    // SSE4.1 implementation (16-byte vectors)
    fn minifySSE41(self: *AdvancedSIMDMinifier, input: []const u8, output: []u8) !usize {
        _ = self;
        
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        const vector_size = 16;
        
        // Process in 16-byte chunks when not in string
        while (i + vector_size <= input.len and !in_string) {
            const chunk = @as(@Vector(16, u8), input[i..i + vector_size][0..vector_size].*);
            
            // Check for quotes in chunk
            const quote_mask = chunk == @as(@Vector(16, u8), @splat('"'));
            const has_quotes = @reduce(.Or, quote_mask);
            
            if (has_quotes) {
                break;
            }
            
            // Vectorized whitespace detection
            const is_whitespace = blk: {
                const is_space = chunk == @as(@Vector(16, u8), @splat(' '));
                const is_tab = chunk == @as(@Vector(16, u8), @splat('\t'));
                const is_newline = chunk == @as(@Vector(16, u8), @splat('\n'));
                const is_cr = chunk == @as(@Vector(16, u8), @splat('\r'));
                break :blk @select(bool, is_space, @as(@Vector(16, bool), @splat(true)), @select(bool, is_tab, @as(@Vector(16, bool), @splat(true)), @select(bool, is_newline, @as(@Vector(16, bool), @splat(true)), @select(bool, is_cr, @as(@Vector(16, bool), @splat(true)), @as(@Vector(16, bool), @splat(false))))));
            };
            
            // Copy non-whitespace characters
            comptime var j = 0;
            inline while (j < vector_size) : (j += 1) {
                if (!is_whitespace[j]) {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = chunk[j];
                    out_pos += 1;
                }
            }
            
            i += vector_size;
        }
        
        // Scalar processing for remaining
        while (i < input.len) {
            const c = input[i];
            
            if (in_string) {
                if (out_pos >= output.len) return error.OutputBufferTooSmall;
                output[out_pos] = c;
                out_pos += 1;
                
                if (c == '\\' and !escaped) {
                    escaped = true;
                } else if (c == '"' and !escaped) {
                    in_string = false;
                    escaped = false;
                } else {
                    escaped = false;
                }
            } else {
                if (c == '"') {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                    in_string = true;
                } else if (!isWhitespace(c)) {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                }
            }
            
            i += 1;
        }
        
        return out_pos;
    }
    
    // SSE2 implementation (16-byte vectors, basic)
    fn minifySSE2(self: *AdvancedSIMDMinifier, input: []const u8, output: []u8) !usize {
        // Use same logic as SSE4.1 but with basic SSE2 instructions
        return self.minifySSE41(input, output);
    }
    
    // Scalar fallback
    fn minifyScalar(self: *AdvancedSIMDMinifier, input: []const u8, output: []u8) !usize {
        _ = self;
        
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        while (i < input.len) {
            const c = input[i];
            
            if (in_string) {
                if (out_pos >= output.len) return error.OutputBufferTooSmall;
                output[out_pos] = c;
                out_pos += 1;
                
                if (c == '\\' and !escaped) {
                    escaped = true;
                } else if (c == '"' and !escaped) {
                    in_string = false;
                    escaped = false;
                } else {
                    escaped = false;
                }
            } else {
                if (c == '"') {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                    in_string = true;
                } else if (!isWhitespace(c)) {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                }
            }
            
            i += 1;
        }
        
        return out_pos;
    }
    
    inline fn isWhitespace(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }
    
    // Get information about the detected SIMD capabilities
    pub fn getSIMDInfo(self: *AdvancedSIMDMinifier) SIMDInfo {
        return SIMDInfo{
            .level = self.simd_level,
            .vector_size = self.simd_level.getVectorSize(),
            .name = self.simd_level.getName(),
            .features = self.cpu_features,
        };
    }
    
    pub const SIMDInfo = struct {
        level: CPUFeatures.SIMDLevel,
        vector_size: usize,
        name: []const u8,
        features: CPUFeatures,
    };
};