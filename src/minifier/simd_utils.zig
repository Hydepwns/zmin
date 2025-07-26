const std = @import("std");
const builtin = @import("builtin");

/// SIMD utilities for high-performance JSON processing
pub const SimdUtils = struct {
    /// Vector size for SIMD operations (256-bit AVX2 or 128-bit NEON/SSE)
    pub const vector_size = if (builtin.cpu.arch == .x86_64) 32 else 16;
    pub const VectorType = @Vector(vector_size, u8);
    
    /// SIMD character classification for fast whitespace detection
    pub fn classifyCharsSimd(input: []const u8, offset: usize) CharClassification {
        if (offset + vector_size > input.len) {
            return CharClassification{ .whitespace_mask = 0, .quote_mask = 0, .backslash_mask = 0, .structural_mask = 0 };
        }
        
        const chunk = input[offset..][0..vector_size];
        const vec: VectorType = chunk.*;
        
        // Create comparison vectors
        const space_vec = @as(VectorType, @splat(' '));
        const tab_vec = @as(VectorType, @splat('\t'));
        const newline_vec = @as(VectorType, @splat('\n'));
        const cr_vec = @as(VectorType, @splat('\r'));
        const quote_vec = @as(VectorType, @splat('"'));
        const backslash_vec = @as(VectorType, @splat('\\'));
        const lbrace_vec = @as(VectorType, @splat('{'));
        const rbrace_vec = @as(VectorType, @splat('}'));
        const lbracket_vec = @as(VectorType, @splat('['));
        const rbracket_vec = @as(VectorType, @splat(']'));
        const colon_vec = @as(VectorType, @splat(':'));
        const comma_vec = @as(VectorType, @splat(','));
        
        // Perform SIMD comparisons
        const space_cmp = vec == space_vec;
        const tab_cmp = vec == tab_vec;
        const newline_cmp = vec == newline_vec;
        const cr_cmp = vec == cr_vec;
        const quote_cmp = vec == quote_vec;
        const backslash_cmp = vec == backslash_vec;
        
        // Convert to masks
        var space_mask: u32 = 0;
        var tab_mask: u32 = 0;
        var newline_mask: u32 = 0;
        var cr_mask: u32 = 0;
        var quote_mask: u32 = 0;
        var backslash_mask: u32 = 0;
        
        inline for (0..vector_size) |i| {
            if (space_cmp[i]) space_mask |= @as(u32, 1) << @intCast(i);
            if (tab_cmp[i]) tab_mask |= @as(u32, 1) << @intCast(i);
            if (newline_cmp[i]) newline_mask |= @as(u32, 1) << @intCast(i);
            if (cr_cmp[i]) cr_mask |= @as(u32, 1) << @intCast(i);
            if (quote_cmp[i]) quote_mask |= @as(u32, 1) << @intCast(i);
            if (backslash_cmp[i]) backslash_mask |= @as(u32, 1) << @intCast(i);
        }
        
        // Combine whitespace masks
        const whitespace_mask = space_mask | tab_mask | newline_mask | cr_mask;
        
        // Structural character masks
        const lbrace_cmp = vec == lbrace_vec;
        const rbrace_cmp = vec == rbrace_vec;
        const lbracket_cmp = vec == lbracket_vec;
        const rbracket_cmp = vec == rbracket_vec;
        const colon_cmp = vec == colon_vec;
        const comma_cmp = vec == comma_vec;
        
        var lbrace_mask: u32 = 0;
        var rbrace_mask: u32 = 0;
        var lbracket_mask: u32 = 0;
        var rbracket_mask: u32 = 0;
        var colon_mask: u32 = 0;
        var comma_mask: u32 = 0;
        
        inline for (0..vector_size) |i| {
            if (lbrace_cmp[i]) lbrace_mask |= @as(u32, 1) << @intCast(i);
            if (rbrace_cmp[i]) rbrace_mask |= @as(u32, 1) << @intCast(i);
            if (lbracket_cmp[i]) lbracket_mask |= @as(u32, 1) << @intCast(i);
            if (rbracket_cmp[i]) rbracket_mask |= @as(u32, 1) << @intCast(i);
            if (colon_cmp[i]) colon_mask |= @as(u32, 1) << @intCast(i);
            if (comma_cmp[i]) comma_mask |= @as(u32, 1) << @intCast(i);
        }
        
        const structural_mask = lbrace_mask | rbrace_mask | lbracket_mask | rbracket_mask | colon_mask | comma_mask;
        
        return CharClassification{
            .whitespace_mask = whitespace_mask,
            .quote_mask = quote_mask,
            .backslash_mask = backslash_mask,
            .structural_mask = structural_mask,
        };
    }
    
    /// Fast SIMD string copy with escape detection
    pub fn copyStringSimd(src: []const u8, dst: []u8, offset: usize, len: usize) CopyResult {
        var src_pos = offset;
        var dst_pos: usize = 0;
        var escape_found = false;
        
        // Process in SIMD chunks
        while (src_pos + vector_size <= offset + len) {
            const chunk = src[src_pos..][0..vector_size];
            const vec: VectorType = chunk.*;
            
            // Check for escape characters
            const backslash_vec = @as(VectorType, @splat('\\'));
            const quote_vec = @as(VectorType, @splat('"'));
            const backslash_cmp = vec == backslash_vec;
            const quote_cmp = vec == quote_vec;
            
            var has_escape = false;
            for (0..vector_size) |i| {
                if (backslash_cmp[i] or quote_cmp[i]) {
                    has_escape = true;
                    break;
                }
            }
            
            if (has_escape) {
                escape_found = true;
                // Fall back to scalar processing for this chunk
                var i: usize = 0;
                while (i < vector_size and src_pos + i < offset + len) : (i += 1) {
                    dst[dst_pos] = src[src_pos + i];
                    dst_pos += 1;
                }
            } else {
                // Fast copy entire vector
                @memcpy(dst[dst_pos..][0..vector_size], chunk);
                dst_pos += vector_size;
            }
            
            src_pos += vector_size;
        }
        
        // Handle remaining bytes
        while (src_pos < offset + len) : (src_pos += 1) {
            dst[dst_pos] = src[src_pos];
            dst_pos += 1;
        }
        
        return CopyResult{
            .bytes_copied = dst_pos,
            .escape_found = escape_found,
        };
    }
    
    /// Find the end of a number using SIMD
    pub fn findNumberEndSimd(input: []const u8, offset: usize) usize {
        var pos = offset;
        
        // Skip sign if present
        if (pos < input.len and (input[pos] == '-' or input[pos] == '+')) {
            pos += 1;
        }
        
        // Process digits in SIMD chunks
        while (pos + vector_size <= input.len) {
            const chunk = input[pos..][0..vector_size];
            const vec: VectorType = chunk.*;
            
            // Create digit range vectors
            const zero_vec = @as(VectorType, @splat('0'));
            const nine_vec = @as(VectorType, @splat('9'));
            const dot_vec = @as(VectorType, @splat('.'));
            const e_lower_vec = @as(VectorType, @splat('e'));
            const e_upper_vec = @as(VectorType, @splat('E'));
            const plus_vec = @as(VectorType, @splat('+'));
            const minus_vec = @as(VectorType, @splat('-'));
            
            // Check if all characters are valid number characters
            const ge_zero = vec >= zero_vec;
            const le_nine = vec <= nine_vec;
            const is_dot_vec = vec == dot_vec;
            const is_e_lower_vec = vec == e_lower_vec;
            const is_e_upper_vec = vec == e_upper_vec;
            const is_plus_vec = vec == plus_vec;
            const is_minus_vec = vec == minus_vec;
            
            // Convert to masks
            var is_digit: u32 = 0;
            var is_dot: u32 = 0;
            var is_e_lower: u32 = 0;
            var is_e_upper: u32 = 0;
            var is_plus: u32 = 0;
            var is_minus: u32 = 0;
            
            inline for (0..vector_size) |i| {
                if (ge_zero[i] and le_nine[i]) is_digit |= @as(u32, 1) << @intCast(i);
                if (is_dot_vec[i]) is_dot |= @as(u32, 1) << @intCast(i);
                if (is_e_lower_vec[i]) is_e_lower |= @as(u32, 1) << @intCast(i);
                if (is_e_upper_vec[i]) is_e_upper |= @as(u32, 1) << @intCast(i);
                if (is_plus_vec[i]) is_plus |= @as(u32, 1) << @intCast(i);
                if (is_minus_vec[i]) is_minus |= @as(u32, 1) << @intCast(i);
            }
            
            const valid_mask = is_digit | is_dot | is_e_lower | is_e_upper | is_plus | is_minus;
            
            // Find first non-number character
            if (valid_mask != 0xFFFFFFFF) {
                // Some character is not a valid number character
                // Find the exact position with scalar fallback
                var i: usize = 0;
                while (i < vector_size and pos + i < input.len) : (i += 1) {
                    const c = input[pos + i];
                    if (!isNumberChar(c)) {
                        return pos + i;
                    }
                }
            }
            
            pos += vector_size;
        }
        
        // Handle remaining bytes
        while (pos < input.len) : (pos += 1) {
            if (!isNumberChar(input[pos])) {
                return pos;
            }
        }
        
        return input.len;
    }
    
    /// Skip whitespace using SIMD - returns position of first non-whitespace
    pub fn skipWhitespaceSimd64(input: []const u8, offset: usize) usize {
        var pos = offset;
        
        while (pos + vector_size <= input.len) {
            const classification = classifyCharsSimd(input, pos);
            
            if (classification.whitespace_mask != 0xFFFFFFFF) {
                // Found non-whitespace, find exact position
                var i: usize = 0;
                while (i < vector_size and pos + i < input.len) : (i += 1) {
                    const c = input[pos + i];
                    if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                        return pos + i;
                    }
                }
            }
            
            pos += vector_size;
        }
        
        // Handle remaining bytes
        while (pos < input.len) : (pos += 1) {
            const c = input[pos];
            if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                return pos;
            }
        }
        
        return input.len;
    }
    
    /// Find structural boundaries (useful for parallel processing)
    pub fn findStructuralBoundarySimd(input: []const u8, offset: usize, target_depth: i32) ?usize {
        var pos = offset;
        var depth: i32 = 0;
        var in_string = false;
        var escape_next = false;
        
        while (pos + vector_size <= input.len) {
            const classification = classifyCharsSimd(input, pos);
            
            // Process structural characters
            if (classification.structural_mask != 0 or classification.quote_mask != 0) {
                // Need scalar processing for accurate depth tracking
                var i: usize = 0;
                while (i < vector_size and pos + i < input.len) : (i += 1) {
                    const c = input[pos + i];
                    
                    if (escape_next) {
                        escape_next = false;
                        continue;
                    }
                    
                    if (c == '\\' and in_string) {
                        escape_next = true;
                        continue;
                    }
                    
                    if (c == '"') {
                        in_string = !in_string;
                    } else if (!in_string) {
                        switch (c) {
                            '{', '[' => depth += 1,
                            '}', ']' => {
                                depth -= 1;
                                if (depth == target_depth) {
                                    return pos + i + 1;
                                }
                            },
                            else => {},
                        }
                    }
                }
            } else {
                // Skip entire vector if no structural characters
                var i: usize = 0;
                while (i < vector_size) : (i += 1) {
                    if (escape_next) {
                        escape_next = false;
                    }
                }
            }
            
            pos += vector_size;
        }
        
        // Handle remaining bytes
        while (pos < input.len) : (pos += 1) {
            const c = input[pos];
            
            if (escape_next) {
                escape_next = false;
                continue;
            }
            
            if (c == '\\' and in_string) {
                escape_next = true;
                continue;
            }
            
            if (c == '"') {
                in_string = !in_string;
            } else if (!in_string) {
                switch (c) {
                    '{', '[' => depth += 1,
                    '}', ']' => {
                        depth -= 1;
                        if (depth == target_depth) {
                            return pos + 1;
                        }
                    },
                    else => {},
                }
            }
        }
        
        return null;
    }
    
    // Helper function
    fn isNumberChar(c: u8) bool {
        return (c >= '0' and c <= '9') or c == '.' or c == 'e' or c == 'E' or c == '+' or c == '-';
    }
};

/// Result of character classification
pub const CharClassification = struct {
    whitespace_mask: u32,
    quote_mask: u32,
    backslash_mask: u32,
    structural_mask: u32,
};

/// Result of SIMD copy operation
pub const CopyResult = struct {
    bytes_copied: usize,
    escape_found: bool,
};