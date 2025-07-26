// TURBO Mode Optimized V2 - Focus on non-string performance
// Key insight: String processing is already fast (300+ MB/s)
// Bottleneck: Whitespace detection in non-string content

const std = @import("std");
const builtin = @import("builtin");
const cpu_detection = @import("cpu_detection");

pub const TurboMinifierOptimizedV2 = struct {
    allocator: std.mem.Allocator,
    
    // Precomputed lookup table for ultra-fast character classification
    non_whitespace_table: [256]bool,
    
    pub fn init(allocator: std.mem.Allocator) TurboMinifierOptimizedV2 {
        var self = TurboMinifierOptimizedV2{
            .allocator = allocator,
            .non_whitespace_table = undefined,
        };
        
        // Initialize lookup table - true means copy the character
        for (0..256) |i| {
            const c = @as(u8, @intCast(i));
            self.non_whitespace_table[i] = (c != ' ' and c != '\t' and c != '\n' and c != '\r');
        }
        
        return self;
    }
    
    pub fn minify(self: *TurboMinifierOptimizedV2, input: []const u8, output: []u8) !usize {
        return self.minifyOptimized(input, output);
    }
    
    // Optimized for the common case: non-string content
    fn minifyOptimized(self: *TurboMinifierOptimizedV2, input: []const u8, output: []u8) !usize {
        const non_ws = &self.non_whitespace_table;
        var out_pos: usize = 0;
        var i: usize = 0;
        
        // Main loop - optimized for non-string content
        while (i < input.len) {
            // Fast scan for quotes - most chunks won't have them
            const chunk_size = @min(256, input.len - i);
            var quote_pos: ?usize = null;
            
            // Unrolled quote scanning for speed
            var j: usize = 0;
            while (j + 8 <= chunk_size) : (j += 8) {
                if (input[i + j] == '"' or 
                    input[i + j + 1] == '"' or
                    input[i + j + 2] == '"' or
                    input[i + j + 3] == '"' or
                    input[i + j + 4] == '"' or
                    input[i + j + 5] == '"' or
                    input[i + j + 6] == '"' or
                    input[i + j + 7] == '"') {
                    // Found quote - find exact position
                    for (j..j + 8) |k| {
                        if (input[i + k] == '"') {
                            quote_pos = k;
                            break;
                        }
                    }
                    break;
                }
            }
            
            // Check remaining bytes if needed
            if (quote_pos == null) {
                while (j < chunk_size) : (j += 1) {
                    if (input[i + j] == '"') {
                        quote_pos = j;
                        break;
                    }
                }
            }
            
            if (quote_pos) |qpos| {
                // Process non-string content up to quote
                const end = i + qpos;
                
                // Ultra-fast whitespace removal using lookup table
                while (i < end) {
                    const c = input[i];
                    // Branchless copy using lookup table
                    output[out_pos] = c;
                    out_pos += @intFromBool(non_ws[c]);
                    i += 1;
                }
                
                // Process string starting at quote
                const string_result = processStringOptimized(input[i..], output[out_pos..]);
                out_pos += string_result.output_len;
                i += string_result.consumed;
            } else {
                // No quotes in chunk - ultra-fast processing
                const end = i + chunk_size;
                
                // Process 8 bytes at a time when possible
                while (i + 8 <= end) {
                    // Unrolled loop for better CPU pipeline usage
                    comptime var unroll = 0;
                    inline while (unroll < 8) : (unroll += 1) {
                        const c = input[i + unroll];
                        output[out_pos] = c;
                        out_pos += @intFromBool(non_ws[c]);
                    }
                    i += 8;
                }
                
                // Process remaining bytes
                while (i < end) {
                    const c = input[i];
                    output[out_pos] = c;
                    out_pos += @intFromBool(non_ws[c]);
                    i += 1;
                }
            }
        }
        
        return out_pos;
    }
    
    // Optimized string processing - already fast, just maintain it
    fn processStringOptimized(input: []const u8, output: []u8) struct { output_len: usize, consumed: usize } {
        if (input.len == 0 or input[0] != '"') {
            return .{ .output_len = 0, .consumed = 0 };
        }
        
        // Find string end efficiently
        var i: usize = 1;
        var escaped = false;
        
        // Scan in chunks for better performance
        while (i + 8 <= input.len) {
            const has_special = blk: {
                for (0..8) |j| {
                    const c = input[i + j];
                    if ((c == '"' and !escaped) or c == '\\') {
                        break :blk true;
                    }
                }
                break :blk false;
            };
            
            if (!has_special) {
                // No special characters - skip ahead
                i += 8;
                escaped = false;
            } else {
                // Process byte by byte
                for (0..8) |j| {
                    const c = input[i + j];
                    if (escaped) {
                        escaped = false;
                    } else if (c == '\\') {
                        escaped = true;
                    } else if (c == '"') {
                        i += j + 1;
                        // Bulk copy entire string
                        @memcpy(output[0..i], input[0..i]);
                        return .{ .output_len = i, .consumed = i };
                    }
                }
                i += 8;
            }
        }
        
        // Process remaining bytes
        while (i < input.len) {
            const c = input[i];
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                i += 1;
                break;
            }
            i += 1;
        }
        
        // Bulk copy entire string
        @memcpy(output[0..i], input[0..i]);
        return .{ .output_len = i, .consumed = i };
    }
};

// Alternative: Table-driven state machine for maximum speed
pub const TurboMinifierTable = struct {
    allocator: std.mem.Allocator,
    
    // State machine tables
    action_table: [256][2]Action,  // [char][state] -> action
    next_state_table: [256][2]u8,  // [char][state] -> next state
    
    const State = enum(u8) {
        normal = 0,
        in_string = 1,
    };
    
    const Action = enum(u8) {
        skip = 0,     // Skip character (whitespace)
        copy = 1,     // Copy character
        copy_string = 2, // Copy and track string state
    };
    
    pub fn init(allocator: std.mem.Allocator) TurboMinifierTable {
        var self = TurboMinifierTable{
            .allocator = allocator,
            .action_table = undefined,
            .next_state_table = undefined,
        };
        
        // Initialize state machine tables
        for (0..256) |i| {
            const c = @as(u8, @intCast(i));
            
            // Normal state (outside string)
            if (c == '"') {
                self.action_table[i][0] = .copy_string;
                self.next_state_table[i][0] = @intFromEnum(State.in_string);
            } else if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.action_table[i][0] = .skip;
                self.next_state_table[i][0] = @intFromEnum(State.normal);
            } else {
                self.action_table[i][0] = .copy;
                self.next_state_table[i][0] = @intFromEnum(State.normal);
            }
            
            // String state
            self.action_table[i][1] = .copy;
            self.next_state_table[i][1] = @intFromEnum(State.in_string);
            if (c == '"') {
                // Note: Doesn't handle escapes - would need more states
                self.next_state_table[i][1] = @intFromEnum(State.normal);
            }
        }
        
        return self;
    }
    
    pub fn minify(self: *TurboMinifierTable, input: []const u8, output: []u8) !usize {
        const actions = &self.action_table;
        const next_states = &self.next_state_table;
        
        var out_pos: usize = 0;
        var state: u8 = @intFromEnum(State.normal);
        var escaped = false;
        
        // Table-driven state machine - minimal branching
        for (input) |c| {
            // Handle escape sequences in strings
            if (state == @intFromEnum(State.in_string) and escaped) {
                output[out_pos] = c;
                out_pos += 1;
                escaped = false;
                continue;
            }
            
            if (state == @intFromEnum(State.in_string) and c == '\\') {
                output[out_pos] = c;
                out_pos += 1;
                escaped = true;
                continue;
            }
            
            // Table lookup for action
            const action = actions[c][state];
            const next_state = next_states[c][state];
            
            // Execute action
            switch (action) {
                .skip => {},
                .copy, .copy_string => {
                    output[out_pos] = c;
                    out_pos += 1;
                },
            }
            
            state = next_state;
        }
        
        return out_pos;
    }
};