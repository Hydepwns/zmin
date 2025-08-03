const std = @import("std");
const Token = @import("../streaming/parser.zig").Token;
const TokenType = @import("../streaming/parser.zig").TokenType;
const TokenStream = @import("../streaming/parser.zig").TokenStream;
const OutputStream = @import("pipeline.zig").OutputStream;
const FilterConfig = @import("pipeline.zig").FilterConfig;

/// Field path tracking for nested objects
pub const FieldPath = struct {
    segments: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) FieldPath {
        return .{
            .segments = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *FieldPath) void {
        self.segments.deinit();
    }
    
    pub fn push(self: *FieldPath, segment: []const u8) !void {
        try self.segments.append(segment);
    }
    
    pub fn pop(self: *FieldPath) void {
        if (self.segments.items.len > 0) {
            _ = self.segments.pop();
        }
    }
    
    pub fn matches(self: *const FieldPath, pattern: []const u8, case_sensitive: bool) bool {
        const path = self.toString() catch return false;
        defer self.allocator.free(path);
        
        if (case_sensitive) {
            return std.mem.eql(u8, path, pattern) or matchesWildcard(path, pattern);
        } else {
            return std.ascii.eqlIgnoreCase(path, pattern) or matchesWildcardIgnoreCase(path, pattern);
        }
    }
    
    pub fn toString(self: *const FieldPath) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();
        
        for (self.segments.items, 0..) |segment, i| {
            if (i > 0) try result.append('.');
            try result.appendSlice(segment);
        }
        
        return self.allocator.dupe(u8, result.items);
    }
};

/// Check if a path matches a wildcard pattern
fn matchesWildcard(path: []const u8, pattern: []const u8) bool {
    var path_idx: usize = 0;
    var pattern_idx: usize = 0;
    var star_idx: ?usize = null;
    var star_match_idx: usize = 0;
    
    while (path_idx < path.len) {
        if (pattern_idx < pattern.len and (pattern[pattern_idx] == path[path_idx] or pattern[pattern_idx] == '?')) {
            path_idx += 1;
            pattern_idx += 1;
        } else if (pattern_idx < pattern.len and pattern[pattern_idx] == '*') {
            star_idx = pattern_idx;
            star_match_idx = path_idx;
            pattern_idx += 1;
        } else if (star_idx != null) {
            pattern_idx = star_idx.? + 1;
            star_match_idx += 1;
            path_idx = star_match_idx;
        } else {
            return false;
        }
    }
    
    while (pattern_idx < pattern.len and pattern[pattern_idx] == '*') {
        pattern_idx += 1;
    }
    
    return pattern_idx == pattern.len;
}

/// Check if a path matches a wildcard pattern (case insensitive)
fn matchesWildcardIgnoreCase(path: []const u8, pattern: []const u8) bool {
    var path_idx: usize = 0;
    var pattern_idx: usize = 0;
    var star_idx: ?usize = null;
    var star_match_idx: usize = 0;
    
    while (path_idx < path.len) {
        if (pattern_idx < pattern.len and 
            (std.ascii.toLower(pattern[pattern_idx]) == std.ascii.toLower(path[path_idx]) or 
             pattern[pattern_idx] == '?')) {
            path_idx += 1;
            pattern_idx += 1;
        } else if (pattern_idx < pattern.len and pattern[pattern_idx] == '*') {
            star_idx = pattern_idx;
            star_match_idx = path_idx;
            pattern_idx += 1;
        } else if (star_idx != null) {
            pattern_idx = star_idx.? + 1;
            star_match_idx += 1;
            path_idx = star_match_idx;
        } else {
            return false;
        }
    }
    
    while (pattern_idx < pattern.len and pattern[pattern_idx] == '*') {
        pattern_idx += 1;
    }
    
    return pattern_idx == pattern.len;
}

/// Field filtering state machine
pub const FieldFilterState = struct {
    const Self = @This();
    
    /// Current field path
    path: FieldPath,
    
    /// Stack of object/array depths and whether they're included
    depth_stack: std.ArrayList(DepthInfo),
    
    /// Current field name (if inside an object)
    current_field: ?[]const u8 = null,
    
    /// Whether we're currently skipping content
    skipping: bool = false,
    
    /// Whether the last token was a comma
    last_was_comma: bool = false,
    
    /// Whether we need a comma before the next value
    need_comma: bool = false,
    
    /// Track if we've written the field name but not the value yet
    field_name_written: bool = false,
    
    const DepthInfo = struct {
        is_array: bool,
        is_included: bool,
        element_count: usize = 0,
        written_count: usize = 0,
    };
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .path = FieldPath.init(allocator),
            .depth_stack = std.ArrayList(DepthInfo).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.path.deinit();
        self.depth_stack.deinit();
    }
    
    pub fn shouldIncludeField(self: *const Self, config: FilterConfig) bool {
        // If we're at root level, always include
        if (self.path.segments.items.len == 0) return true;
        
        const current_path = self.path.toString() catch return false;
        defer self.path.allocator.free(current_path);
        
        // Check exclusions first
        if (config.exclude) |exclude_list| {
            for (exclude_list) |pattern| {
                if (self.path.matches(pattern, config.case_sensitive)) {
                    return false;
                }
            }
        }
        
        // Check inclusions
        if (config.include) |include_list| {
            // Check if current path matches any pattern
            for (include_list) |pattern| {
                if (self.path.matches(pattern, config.case_sensitive)) {
                    return true;
                }
                
                // Check if current path is a parent of any included pattern
                // For example, if pattern is "user.profile.name" and current path is "user" or "user.profile"
                if (std.mem.startsWith(u8, pattern, current_path)) {
                    // Make sure it's a proper parent (followed by a dot)
                    if (pattern.len > current_path.len and pattern[current_path.len] == '.') {
                        return true;
                    }
                }
            }
            // If include list is specified but no match, exclude by default
            return false;
        }
        
        // No include list specified, include by default
        return true;
    }
    
    pub fn enterObject(self: *Self, included: bool) !void {
        try self.depth_stack.append(.{
            .is_array = false,
            .is_included = included,
        });
    }
    
    pub fn enterArray(self: *Self, included: bool) !void {
        try self.depth_stack.append(.{
            .is_array = true,
            .is_included = included,
        });
    }
    
    pub fn exitDepth(self: *Self) void {
        if (self.depth_stack.items.len > 0) {
            _ = self.depth_stack.pop();
        }
        if (!self.isInArray()) {
            self.path.pop();
        }
    }
    
    pub fn isInArray(self: *const Self) bool {
        if (self.depth_stack.items.len == 0) return false;
        return self.depth_stack.items[self.depth_stack.items.len - 1].is_array;
    }
    
    pub fn getCurrentDepth(self: *Self) ?*DepthInfo {
        if (self.depth_stack.items.len == 0) return null;
        return &self.depth_stack.items[self.depth_stack.items.len - 1];
    }
    
    pub fn isCurrentDepthIncluded(self: *const Self) bool {
        if (self.depth_stack.items.len == 0) return true;
        return self.depth_stack.items[self.depth_stack.items.len - 1].is_included;
    }
};

/// Execute field filtering transformation
pub fn executeFieldFiltering(
    config: FilterConfig,
    input: *const TokenStream,
    output: *OutputStream,
    allocator: std.mem.Allocator,
) !void {
    var state = FieldFilterState.init(allocator);
    defer state.deinit();
    
    var input_copy = input.*;
    input_copy.reset();
    
    while (input_copy.hasMore()) {
        const token = input_copy.getCurrentToken() orelse {
            input_copy.advance();
            continue;
        };
        
        try processToken(&state, token, config, input.input_data, output);
        input_copy.advance();
    }
}

fn processToken(
    state: *FieldFilterState,
    token: Token,
    config: FilterConfig,
    input_data: []const u8,
    output: *OutputStream,
) !void {
    switch (token.token_type) {
        .object_start => {
            const included = state.isCurrentDepthIncluded();
            if (included and !state.skipping) {
                // For object values, only write if we've written the field name
                if (!state.isInArray() and state.current_field != null and !state.field_name_written) {
                    // Skip this object
                } else {
                    // Write the object start
                    if (state.isInArray()) {
                        // Array element - write comma if needed
                        if (state.getCurrentDepth()) |depth| {
                            if (depth.element_count > 0) {
                                try output.write(",");
                            }
                            depth.element_count += 1;
                        }
                    } else if (state.field_name_written) {
                        // Object field value - increment written count
                        if (state.getCurrentDepth()) |depth| {
                            depth.written_count += 1;
                        }
                    }
                    try output.writeToken(token, input_data);
                }
            }
            try state.enterObject(included and !state.skipping);
        },
        
        .array_start => {
            const included = state.isCurrentDepthIncluded();
            if (included and !state.skipping) {
                // For array values, only write if we've written the field name
                if (!state.isInArray() and state.current_field != null and !state.field_name_written) {
                    // Skip this array
                } else {
                    // Write the array start
                    if (state.isInArray()) {
                        // Array element - write comma if needed
                        if (state.getCurrentDepth()) |depth| {
                            if (depth.element_count > 0) {
                                try output.write(",");
                            }
                            depth.element_count += 1;
                        }
                    } else if (state.field_name_written) {
                        // Object field value - increment written count
                        if (state.getCurrentDepth()) |depth| {
                            depth.written_count += 1;
                        }
                    }
                    try output.writeToken(token, input_data);
                }
            }
            try state.enterArray(included and !state.skipping);
        },
        
        .object_end, .array_end => {
            const depth_info = state.getCurrentDepth();
            const was_included = state.isCurrentDepthIncluded();
            
            state.exitDepth();
            
            // Update skipping state
            if (state.current_field != null and !state.isInArray()) {
                state.current_field = null;
                state.skipping = false;
            }
            
            if (was_included and !state.skipping) {
                try output.writeToken(token, input_data);
                // Set need_comma for parent depth if we wrote something
                if (depth_info) |info| {
                    if (info.written_count > 0 and state.getCurrentDepth() != null) {
                        state.need_comma = true;
                    }
                }
            }
        },
        
        .string => {
            // Check if this is a field name or value
            if (!state.isInArray() and state.current_field == null) {
                // This is a field name
                const field_name = input_data[token.start..token.end];
                const unquoted_field = if (field_name.len >= 2 and field_name[0] == '"' and field_name[field_name.len - 1] == '"')
                    field_name[1..field_name.len - 1]
                else
                    field_name;
                
                state.current_field = unquoted_field;
                try state.path.push(unquoted_field);
                
                // Check if this field should be included
                const should_include = state.shouldIncludeField(config);
                state.skipping = !should_include;
                
                if (should_include and state.isCurrentDepthIncluded()) {
                    // Write comma if needed (only if we've written fields before)
                    if (state.getCurrentDepth()) |depth| {
                        if (depth.written_count > 0) {
                            try output.write(",");
                        }
                    }
                    try output.writeToken(token, input_data);
                    state.field_name_written = true;
                }
            } else {
                // This is a field value
                if (!state.skipping and state.isCurrentDepthIncluded() and state.field_name_written) {
                    try output.writeToken(token, input_data);
                    // Increment written count after successfully writing a field value
                    if (!state.isInArray() and state.getCurrentDepth() != null) {
                        if (state.getCurrentDepth()) |depth| {
                            depth.written_count += 1;
                        }
                    }
                }
                
                // Reset field tracking after value
                if (!state.isInArray() and state.current_field != null) {
                    state.path.pop();
                    state.current_field = null;
                    state.skipping = false;
                    state.field_name_written = false;
                }
            }
        },
        
        .colon => {
            if (!state.skipping and state.isCurrentDepthIncluded() and state.field_name_written) {
                try output.writeToken(token, input_data);
            }
        },
        
        .comma => {
            // Handle comma based on context
            if (!state.isInArray() and state.current_field != null) {
                // We're after a field value, reset state
                state.path.pop();
                state.current_field = null;
                state.skipping = false;
            }
            
            // Don't write comma here - we'll add it when needed before the next element
            state.last_was_comma = true;
        },
        
        .number, .boolean_true, .boolean_false, .null => {
            if (!state.skipping and state.isCurrentDepthIncluded()) {
                if (state.isInArray()) {
                    // Array element - write comma if needed
                    if (state.getCurrentDepth()) |depth| {
                        if (depth.element_count > 0) {
                            try output.write(",");
                        }
                        depth.element_count += 1;
                    }
                    try output.writeToken(token, input_data);
                } else if (state.field_name_written) {
                    // Object field value
                    try output.writeToken(token, input_data);
                    if (state.getCurrentDepth()) |depth| {
                        depth.written_count += 1;
                    }
                }
            }
            
            // Reset field tracking after value only if in object context
            if (!state.isInArray() and state.current_field != null) {
                state.path.pop();
                state.current_field = null;
                state.skipping = false;
                state.field_name_written = false;
            }
        },
        
        .whitespace, .comment => {
            // Skip whitespace and comments in filtered output
        },
        
        .eof => {
            // End of stream
        },
        
        .parse_error => {
            return error.ParseError;
        },
    }
}