// TURBO Mode Streaming - Maximum bulk copy efficiency
// Target: 800+ MB/s through streaming bulk operations
// Key insights:
// 1. Process massive chunks with minimal per-byte logic
// 2. Use memcpy for everything possible 
// 3. Defer complex logic to string boundaries only
// 4. Optimize for the common case (non-string content)

const std = @import("std");
const builtin = @import("builtin");
const cpu_detection = @import("cpu_detection");

pub const TurboMinifierStreaming = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) TurboMinifierStreaming {
        return .{ .allocator = allocator };
    }
    
    pub fn minify(self: *TurboMinifierStreaming, input: []const u8, output: []u8) !usize {
        return self.minifyStreaming(input, output);
    }
    
    // Ultra-fast streaming approach - process in massive chunks
    fn minifyStreaming(self: *TurboMinifierStreaming, input: []const u8, output: []u8) !usize {
        _ = self;
        if (input.len == 0) return 0;
        
        var out_pos: usize = 0;
        var i: usize = 0;
        
        // Process in HUGE chunks for maximum memory bandwidth
        const mega_chunk_size = 4096; // 4KB chunks
        
        while (i + mega_chunk_size <= input.len) {
            // Fast scan for quotes in the entire chunk
            const chunk_start = i;
            const chunk_end = i + mega_chunk_size;
            
            const first_quote = findFirstQuote(input[chunk_start..chunk_end]);
            
            if (first_quote) |quote_offset| {
                // Quote found - process up to quote with bulk whitespace removal
                const process_end = chunk_start + quote_offset;
                const processed_len = bulkRemoveWhitespace(input[i..process_end], output[out_pos..]);
                out_pos += processed_len;
                i = process_end;
                
                // Handle string starting at quote
                const string_result = processString(input[i..], output[out_pos..]);
                out_pos += string_result.output_len;
                i += string_result.consumed;
            } else {
                // No quotes - ultra-fast bulk whitespace removal for entire chunk
                const processed_len = bulkRemoveWhitespace(input[chunk_start..chunk_end], output[out_pos..]);
                out_pos += processed_len;
                i = chunk_end;
            }
        }
        
        // Process remaining bytes
        while (i < input.len) {
            if (input[i] == '"') {
                // Handle string
                const string_result = processString(input[i..], output[out_pos..]);
                out_pos += string_result.output_len;
                i += string_result.consumed;
            } else {
                // Single character processing for remainder
                const c = input[i];
                if (!isWhitespace(c)) {
                    output[out_pos] = c;
                    out_pos += 1;
                }
                i += 1;
            }
        }
        
        return out_pos;
    }
    
    // Ultra-fast quote finding using word-aligned scanning
    fn findFirstQuote(chunk: []const u8) ?usize {
        var i: usize = 0;
        
        // Process 8 bytes at a time for better memory bandwidth
        while (i + 8 <= chunk.len) {
            // Load 8 bytes as u64 and check for quotes
            const word = std.mem.bytesToValue(u64, chunk[i..i+8]);
            
            // Check each byte in the u64 for quote character
            const quote_pattern: u64 = 0x2222222222222222; // '"' repeated 8 times
            const xor_result = word ^ quote_pattern;
            
            // Check if any byte became zero (indicating a match)
            const has_zero_byte = (xor_result -% 0x0101010101010101) & (~xor_result) & 0x8080808080808080;
            
            if (has_zero_byte != 0) {
                // Found a quote somewhere in these 8 bytes - find exact position
                for (0..8) |j| {
                    if (chunk[i + j] == '"') {
                        return i + j;
                    }
                }
            }
            i += 8;
        }
        
        // Check remaining bytes
        while (i < chunk.len) {
            if (chunk[i] == '"') {
                return i;
            }
            i += 1;
        }
        
        return null;
    }
    
    // Bulk whitespace removal with maximum memory efficiency
    fn bulkRemoveWhitespace(input: []const u8, output: []u8) usize {
        var out_pos: usize = 0;
        var i: usize = 0;
        
        // Process in 16-byte chunks for better cache efficiency
        while (i + 16 <= input.len) {
            // Load 16 bytes and process efficiently
            var non_ws_count: usize = 0;
            var temp_buffer: [16]u8 = undefined;
            
            // Collect non-whitespace bytes
            for (0..16) |j| {
                const c = input[i + j];
                if (!isWhitespace(c)) {
                    temp_buffer[non_ws_count] = c;
                    non_ws_count += 1;
                }
            }
            
            // Bulk copy non-whitespace bytes
            if (non_ws_count > 0) {
                @memcpy(output[out_pos..out_pos + non_ws_count], temp_buffer[0..non_ws_count]);
                out_pos += non_ws_count;
            }
            i += 16;
        }
        
        // Process remaining bytes
        while (i < input.len) {
            const c = input[i];
            if (!isWhitespace(c)) {
                output[out_pos] = c;
                out_pos += 1;
            }
            i += 1;
        }
        
        return out_pos;
    }
    
    // Process entire string with bulk copying
    fn processString(input: []const u8, output: []u8) struct { output_len: usize, consumed: usize } {
        if (input.len == 0 or input[0] != '"') {
            return .{ .output_len = 0, .consumed = 0 };
        }
        
        var i: usize = 1; // Skip opening quote
        var escaped = false;
        
        // Find string end efficiently
        while (i < input.len) {
            const c = input[i];
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                i += 1; // Include closing quote
                break;
            }
            i += 1;
        }
        
        // Bulk copy entire string including quotes
        @memcpy(output[0..i], input[0..i]);
        return .{ .output_len = i, .consumed = i };
    }
    
    inline fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }
};

// Even more aggressive approach - assume mostly non-strings
pub const TurboMinifierMegaBulk = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) TurboMinifierMegaBulk {
        return .{ .allocator = allocator };
    }
    
    pub fn minify(self: *TurboMinifierMegaBulk, input: []const u8, output: []u8) !usize {
        return self.minifyMegaBulk(input, output);
    }
    
    // Maximum bulk processing - handle strings as exceptions
    fn minifyMegaBulk(self: *TurboMinifierMegaBulk, input: []const u8, output: []u8) !usize {
        if (input.len == 0) return 0;
        
        var out_pos: usize = 0;
        var i: usize = 0;
        
        // Scan for ALL quotes first to create processing plan
        var quote_positions = std.ArrayList(usize).init(self.allocator);
        defer quote_positions.deinit();
        
        // Fast quote scanning
        var scan_pos: usize = 0;
        while (scan_pos < input.len) {
            if (input[scan_pos] == '"') {
                try quote_positions.append(scan_pos);
            }
            scan_pos += 1;
        }
        
        // Process between quotes with maximum bulk efficiency
        var quote_idx: usize = 0;
        while (i < input.len) {
            var next_quote_pos: usize = input.len;
            if (quote_idx < quote_positions.items.len) {
                next_quote_pos = quote_positions.items[quote_idx];
            }
            
            if (i < next_quote_pos) {
                // Bulk process non-string content
                const chunk_len = next_quote_pos - i;
                const processed_len = megaBulkWhitespaceRemoval(input[i..i + chunk_len], output[out_pos..]);
                out_pos += processed_len;
                i = next_quote_pos;
            }
            
            if (i < input.len and input[i] == '"') {
                // Process string
                const string_result = processStringFast(input[i..], output[out_pos..]);
                out_pos += string_result.output_len;
                i += string_result.consumed;
                quote_idx += 2; // Skip to next string (assuming paired quotes)
            }
        }
        
        return out_pos;
    }
    
    // Maximum bulk whitespace removal
    fn megaBulkWhitespaceRemoval(input: []const u8, output: []u8) usize {
        var out_pos: usize = 0;
        var i: usize = 0;
        
        // Process in 64-byte super-chunks
        while (i + 64 <= input.len) {
            var temp_buffer: [64]u8 = undefined;
            var temp_pos: usize = 0;
            
            // Collect all non-whitespace in chunk
            for (0..64) |j| {
                const c = input[i + j];
                if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                    temp_buffer[temp_pos] = c;
                    temp_pos += 1;
                }
            }
            
            // Single bulk copy
            @memcpy(output[out_pos..out_pos + temp_pos], temp_buffer[0..temp_pos]);
            out_pos += temp_pos;
            i += 64;
        }
        
        // Process remainder
        while (i < input.len) {
            const c = input[i];
            if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                output[out_pos] = c;
                out_pos += 1;
            }
            i += 1;
        }
        
        return out_pos;
    }
    
    fn processStringFast(input: []const u8, output: []u8) struct { output_len: usize, consumed: usize } {
        if (input.len == 0 or input[0] != '"') {
            return .{ .output_len = 0, .consumed = 0 };
        }
        
        // Find string end without escape handling for max speed
        var i: usize = 1;
        while (i < input.len and input[i] != '"') {
            i += 1;
        }
        if (i < input.len) i += 1; // Include closing quote
        
        // Bulk copy
        @memcpy(output[0..i], input[0..i]);
        return .{ .output_len = i, .consumed = i };
    }
};