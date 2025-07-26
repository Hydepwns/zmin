// TURBO Mode - Maximum speed JSON minifier using SIMD
// Target: 2-3 GB/s throughput with full document in memory

const std = @import("std");
const builtin = @import("builtin");
const cpu_detection = @import("cpu_detection");

pub const TurboMinifier = struct {
    allocator: std.mem.Allocator,
    simd_strategy: cpu_detection.SimdStrategy,
    
    pub fn init(allocator: std.mem.Allocator) TurboMinifier {
        return .{
            .allocator = allocator,
            .simd_strategy = cpu_detection.getOptimalSimdStrategy(),
        };
    }
    
    pub fn minify(self: *TurboMinifier, input: []const u8, output: []u8) !usize {
        // Choose implementation based on detected SIMD support
        return switch (self.simd_strategy) {
            .avx512 => self.minifyAvx512(input, output),
            .avx2 => self.minifyAvx2(input, output),
            .sse2 => self.minifySse2(input, output),
            .scalar => self.minifyScalar(input, output),
        };
    }
    
    // AVX2 implementation - 32 byte vectors (optimized)
    fn minifyAvx2(self: *TurboMinifier, input: []const u8, output: []u8) !usize {
        _ = self;
        const vector_size = 32;
        const Vector = @Vector(vector_size, u8);
        
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        // Structural character vectors
        const quote_vec = @as(Vector, @splat(@as(u8, '"')));
        const space_vec = @as(Vector, @splat(@as(u8, ' ')));
        const tab_vec = @as(Vector, @splat(@as(u8, '\t')));
        const newline_vec = @as(Vector, @splat(@as(u8, '\n')));
        const return_vec = @as(Vector, @splat(@as(u8, '\r')));
        
        // Process chunks without strict alignment requirements (unaligned loads are fast on modern CPUs)
        while (i + vector_size <= input.len) {
            if (!in_string) {
                // Load chunk (unaligned access is acceptable for performance)
                const chunk: Vector = @bitCast(input[i..i+vector_size][0..vector_size].*);
                
                // Find quotes and whitespace
                const quote_mask = chunk == quote_vec;
                const space_mask = chunk == space_vec;
                const tab_mask = chunk == tab_vec;
                const newline_mask = chunk == newline_vec;
                const return_mask = chunk == return_vec;
                
                // Combine whitespace masks using logical operations
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
                // In string - process in chunks when possible
                const chunk_start = i;
                var chunk_end = i;
                
                // Find the end of a safe chunk (no quotes or backslashes)
                while (chunk_end < input.len and chunk_end < i + vector_size) {
                    const c = input[chunk_end];
                    if (c == '"' and !escaped) {
                        // End of string
                        if (chunk_end > chunk_start) {
                            // Copy the chunk
                            @memcpy(output[out_pos..out_pos+(chunk_end-chunk_start)], input[chunk_start..chunk_end]);
                            out_pos += chunk_end - chunk_start;
                        }
                        // Copy the quote
                        output[out_pos] = c;
                        out_pos += 1;
                        in_string = false;
                        i = chunk_end + 1;
                        break;
                    } else if (c == '\\' and !escaped) {
                        escaped = true;
                        chunk_end += 1;
                    } else {
                        escaped = false;
                        chunk_end += 1;
                    }
                }
                
                // If we didn't find end of string, copy what we have
                if (in_string and chunk_end > chunk_start) {
                    @memcpy(output[out_pos..out_pos+(chunk_end-chunk_start)], input[chunk_start..chunk_end]);
                    out_pos += chunk_end - chunk_start;
                    i = chunk_end;
                }
            }
        }
        
        // Process remaining bytes
        while (i < input.len) {
            const c = input[i];
            if (in_string) {
                output[out_pos] = c;
                out_pos += 1;
                if (escaped) {
                    escaped = false;
                } else if (c == '\\') {
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
    
    // SSE2 implementation - 16 byte vectors
    fn minifySse2(self: *TurboMinifier, input: []const u8, output: []u8) !usize {
        const vector_size = 16;
        const Vector = @Vector(vector_size, u8);
        
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        const escaped = false;
        
        // Process in 16-byte chunks
        while (i + vector_size <= input.len and !in_string) {
            // Check alignment
            if (@intFromPtr(&input[i]) % @alignOf(Vector) != 0) {
                // Not aligned - process byte by byte
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
                continue;
            }
            
            const chunk = @as(*const Vector, @ptrCast(@alignCast(&input[i]))).*;
            
            // Check for quotes
            const quote_vec = @as(Vector, @splat(@as(u8, '"')));
            const has_quote = @reduce(.Or, chunk == quote_vec);
            
            if (has_quote) {
                // Process byte by byte until quote
                for (0..vector_size) |j| {
                    const c = input[i + j];
                    if (c == '"') {
                        output[out_pos] = c;
                        out_pos += 1;
                        in_string = true;
                        i += j + 1;
                        break;
                    } else if (!isWhitespace(c)) {
                        output[out_pos] = c;
                        out_pos += 1;
                    }
                }
            } else {
                // Copy non-whitespace
                for (0..vector_size) |j| {
                    const c = chunk[j];
                    if (!isWhitespace(c)) {
                        output[out_pos] = c;
                        out_pos += 1;
                    }
                }
                i += vector_size;
            }
        }
        
        // Handle remainder with scalar code
        return self.processRemainder(input, output, i, out_pos, in_string, escaped);
    }
    
    // AVX512 implementation would go here
    fn minifyAvx512(self: *TurboMinifier, input: []const u8, output: []u8) !usize {
        // For now, fall back to AVX2
        return self.minifyAvx2(input, output);
    }
    
    // Scalar fallback
    fn minifyScalar(self: *TurboMinifier, input: []const u8, output: []u8) !usize {
        return self.processRemainder(input, output, 0, 0, false, false);
    }
    
    // Common remainder processing
    fn processRemainder(
        self: *TurboMinifier,
        input: []const u8,
        output: []u8,
        start_pos: usize,
        start_out: usize,
        start_in_string: bool,
        start_escaped: bool,
    ) !usize {
        _ = self;
        var i = start_pos;
        var out_pos = start_out;
        var in_string = start_in_string;
        var escaped = start_escaped;
        
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
    
    inline fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }
    
    pub fn getInfo(self: *TurboMinifier) void {
        const stdout = std.io.getStdOut().writer();
        stdout.print("TURBO Minifier using {s} strategy\n", .{@tagName(self.simd_strategy)}) catch {};
        stdout.print("Vector width: {} bytes\n", .{self.simd_strategy.getSimdWidth()}) catch {};
    }
};