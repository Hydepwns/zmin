// TURBO Mode Scalar - Ultra-simplified approach targeting 800+ MB/s
// Based on roadmap insight: "Advanced scalar techniques outperform complex SIMD"
// Key optimizations:
// 1. ZERO SIMD - pure scalar efficiency
// 2. Minimal branching using lookup tables
// 3. Bulk operations with pointer arithmetic
// 4. Cache-friendly memory access patterns

const std = @import("std");
const builtin = @import("builtin");
const cpu_detection = @import("cpu_detection");

pub const TurboMinifierScalar = struct {
    allocator: std.mem.Allocator,
    
    // Pre-computed lookup tables for branch elimination
    whitespace_table: [256]bool,
    
    pub fn init(allocator: std.mem.Allocator) TurboMinifierScalar {
        var self = TurboMinifierScalar{
            .allocator = allocator,
            .whitespace_table = [_]bool{false} ** 256,
        };
        
        // Initialize whitespace lookup table
        self.whitespace_table[' '] = true;
        self.whitespace_table['\t'] = true; 
        self.whitespace_table['\n'] = true;
        self.whitespace_table['\r'] = true;
        
        return self;
    }
    
    pub fn minify(self: *TurboMinifierScalar, input: []const u8, output: []u8) !usize {
        return self.minifyScalarOptimized(input, output);
    }
    
    // Ultra-optimized scalar implementation
    fn minifyScalarOptimized(self: *TurboMinifierScalar, input: []const u8, output: []u8) !usize {
        if (input.len == 0) return 0;
        
        const whitespace_table = &self.whitespace_table;
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        // Process in large chunks to improve cache behavior
        const chunk_size = 64;
        
        // Main processing loop - optimized for CPU pipeline efficiency
        while (i + chunk_size <= input.len) {
            const chunk_end = i + chunk_size;
            
            if (!in_string) {
                // Fast path: scan for quotes first to decide processing strategy
                var quote_pos: ?usize = null;
                var scan_pos = i;
                
                // Unrolled quote scanning for better performance
                while (scan_pos < chunk_end) : (scan_pos += 8) {
                    // Process 8 bytes at once with minimal branching
                    const remaining = @min(8, chunk_end - scan_pos);
                    comptime var unroll_idx = 0;
                    inline while (unroll_idx < 8) : (unroll_idx += 1) {
                        if (unroll_idx < remaining) {
                            if (input[scan_pos + unroll_idx] == '"') {
                                quote_pos = scan_pos + unroll_idx;
                                break;
                            }
                        }
                    }
                    if (quote_pos != null) break;
                }
                
                if (quote_pos) |qpos| {
                    // Process up to quote with whitespace removal
                    while (i < qpos) {
                        const c = input[i];
                        // Branchless whitespace check using lookup table
                        if (!whitespace_table[c]) {
                            output[out_pos] = c;
                            out_pos += 1;
                        }
                        i += 1;
                    }
                    // Add quote and enter string mode
                    output[out_pos] = '"';
                    out_pos += 1;
                    i = qpos + 1;
                    in_string = true;
                } else {
                    // No quotes in chunk - ultra-fast whitespace removal
                    while (i < chunk_end) : (i += 1) {
                        const c = input[i];
                        // Branchless copy using lookup table
                        const is_ws = whitespace_table[c];
                        output[out_pos] = c;
                        out_pos += @intFromBool(!is_ws);
                    }
                }
            } else {
                // String mode - look for string end
                var string_end: ?usize = null;
                var temp_escaped = escaped;
                
                // Fast string end detection
                var scan_pos = i;
                while (scan_pos < chunk_end) : (scan_pos += 1) {
                    const c = input[scan_pos];
                    if (temp_escaped) {
                        temp_escaped = false;
                    } else if (c == '\\') {
                        temp_escaped = true;
                    } else if (c == '"') {
                        string_end = scan_pos;
                        break;
                    }
                }
                
                if (string_end) |send| {
                    // Bulk copy string content
                    const string_len = send - i + 1; // Include closing quote
                    @memcpy(output[out_pos..out_pos + string_len], input[i..i + string_len]);
                    out_pos += string_len;
                    i = send + 1;
                    in_string = false;
                    escaped = false;
                } else {
                    // String continues - bulk copy chunk
                    const chunk_len = chunk_end - i;
                    @memcpy(output[out_pos..out_pos + chunk_len], input[i..chunk_end]);
                    out_pos += chunk_len;
                    i = chunk_end;
                    escaped = temp_escaped;
                }
            }
        }
        
        // Handle remaining bytes with optimized tail processing
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
                } else {
                    // Branchless whitespace filtering
                    const is_ws = whitespace_table[c];
                    output[out_pos] = c;
                    out_pos += @intFromBool(!is_ws);
                }
            }
            i += 1;
        }
        
        return out_pos;
    }
};

// Additional ultra-fast variants for different scenarios
pub const TurboMinifierBranchless = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) TurboMinifierBranchless {
        return .{ .allocator = allocator };
    }
    
    pub fn minify(self: *TurboMinifierBranchless, input: []const u8, output: []u8) !usize {
        _ = self;
        if (input.len == 0) return 0;
        
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string: u8 = 0; // 0 = false, 1 = true
        var escaped: u8 = 0;
        
        // Completely branchless inner loop for maximum CPU efficiency
        while (i < input.len) : (i += 1) {
            const c = input[i];
            
            // Branchless state machine using bit operations
            const is_quote = @intFromBool(c == '"');
            const is_backslash = @intFromBool(c == '\\');
            const is_space = @intFromBool(c == ' ');
            const is_tab = @intFromBool(c == '\t');
            const is_newline = @intFromBool(c == '\n');
            const is_return = @intFromBool(c == '\r');
            const is_whitespace = is_space | is_tab | is_newline | is_return;
            
            // State transitions without branches
            const was_escaped = escaped;
            escaped = (escaped ^ escaped) | (in_string & is_backslash & (1 - was_escaped));
            in_string = in_string ^ (is_quote & (1 - was_escaped));
            
            // Output decision without branches
            const should_output = in_string | ((1 - is_whitespace) & (1 - in_string));
            
            output[out_pos] = c;
            out_pos += should_output;
        }
        
        return out_pos;
    }
};