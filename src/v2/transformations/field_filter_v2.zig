const std = @import("std");
const Token = @import("../streaming/parser.zig").Token;
const TokenType = @import("../streaming/parser.zig").TokenType;
const TokenStream = @import("../streaming/parser.zig").TokenStream;
const OutputStream = @import("pipeline.zig").OutputStream;
const FilterConfig = @import("pipeline.zig").FilterConfig;

/// Execute field filtering transformation with a simpler approach
pub fn executeFieldFiltering(
    config: FilterConfig,
    input: *const TokenStream,
    output: *OutputStream,
    allocator: std.mem.Allocator,
) !void {
    var filter = FieldFilter.init(allocator, config);
    defer filter.deinit();
    
    var input_copy = input.*;
    input_copy.reset();
    
    while (input_copy.hasMore()) {
        const token = input_copy.getCurrentToken() orelse {
            input_copy.advance();
            continue;
        };
        
        try filter.processToken(token, input.input_data, output);
        input_copy.advance();
    }
}

const FieldFilter = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    config: FilterConfig,
    path_stack: std.ArrayList([]const u8),
    depth_stack: std.ArrayList(DepthState),
    current_field: ?[]const u8 = null,
    
    const DepthState = struct {
        is_array: bool,
        is_included: bool,
        items_written: usize = 0,
    };
    
    pub fn init(allocator: std.mem.Allocator, config: FilterConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .path_stack = std.ArrayList([]const u8).init(allocator),
            .depth_stack = std.ArrayList(DepthState).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.path_stack.deinit();
        self.depth_stack.deinit();
    }
    
    fn getCurrentPath(self: *const Self) ![]u8 {
        var path = std.ArrayList(u8).init(self.allocator);
        defer path.deinit();
        
        for (self.path_stack.items, 0..) |segment, i| {
            if (i > 0) try path.append('.');
            try path.appendSlice(segment);
        }
        
        return self.allocator.dupe(u8, path.items);
    }
    
    fn shouldInclude(self: *const Self, field_path: []const u8) bool {
        // Check exclusions first
        if (self.config.exclude) |exclude_list| {
            for (exclude_list) |pattern| {
                if (matchesPattern(field_path, pattern)) {
                    return false;
                }
            }
        }
        
        // Check inclusions
        if (self.config.include) |include_list| {
            // Check if path matches any include pattern
            for (include_list) |pattern| {
                if (matchesPattern(field_path, pattern)) {
                    return true;
                }
                // Check if this path is an ancestor of an included pattern
                if (std.mem.startsWith(u8, pattern, field_path) and 
                    pattern.len > field_path.len and 
                    pattern[field_path.len] == '.') {
                    return true;
                }
            }
            return false;
        }
        
        // No include list, include by default
        return true;
    }
    
    fn matchesPattern(path: []const u8, pattern: []const u8) bool {
        // Simple wildcard matching
        if (std.mem.indexOf(u8, pattern, "*") != null) {
            // For now, just support prefix wildcards like "user.*"
            if (std.mem.endsWith(u8, pattern, ".*")) {
                const prefix = pattern[0..pattern.len - 2];
                return std.mem.startsWith(u8, path, prefix) and
                       (path.len == prefix.len or path[prefix.len] == '.');
            }
        }
        return std.mem.eql(u8, path, pattern);
    }
    
    fn getCurrentDepth(self: *Self) ?*DepthState {
        if (self.depth_stack.items.len == 0) return null;
        return &self.depth_stack.items[self.depth_stack.items.len - 1];
    }
    
    fn isInArray(self: *const Self) bool {
        if (self.depth_stack.items.len == 0) return false;
        return self.depth_stack.items[self.depth_stack.items.len - 1].is_array;
    }
    
    fn isIncluded(self: *const Self) bool {
        if (self.depth_stack.items.len == 0) return true;
        for (self.depth_stack.items) |depth| {
            if (!depth.is_included) return false;
        }
        return true;
    }
    
    pub fn processToken(
        self: *Self,
        token: Token,
        input_data: []const u8,
        output: *OutputStream,
    ) !void {
        switch (token.token_type) {
            .object_start => {
                const parent_included = self.isIncluded();
                var include_this = parent_included;
                
                // Check if this object should be included based on field filtering
                if (parent_included and self.current_field != null and !self.isInArray()) {
                    try self.path_stack.append(self.current_field.?);
                    const path = try self.getCurrentPath();
                    defer self.allocator.free(path);
                    include_this = self.shouldInclude(path);
                    
                    if (!include_this) {
                        // Skip the field name and colon we might have written
                        _ = self.path_stack.pop();
                    }
                }
                
                if (include_this) {
                    // Write comma if needed
                    if (self.getCurrentDepth()) |depth| {
                        if (!self.isInArray() and depth.items_written > 0) {
                            try output.write(",");
                        } else if (self.isInArray() and depth.items_written > 0) {
                            try output.write(",");
                        }
                    }
                    
                    // Write field name if we have one
                    if (self.current_field != null and !self.isInArray()) {
                        try output.write("\"");
                        try output.write(self.current_field.?);
                        try output.write("\":");
                    }
                    
                    try output.writeToken(token, input_data);
                    
                    // Update parent's item count
                    if (self.getCurrentDepth()) |depth| {
                        depth.items_written += 1;
                    }
                }
                
                // Push new depth
                try self.depth_stack.append(.{
                    .is_array = false,
                    .is_included = include_this,
                });
                
                self.current_field = null;
            },
            
            .array_start => {
                const parent_included = self.isIncluded();
                var include_this = parent_included;
                
                // Check if this array should be included based on field filtering
                if (parent_included and self.current_field != null and !self.isInArray()) {
                    try self.path_stack.append(self.current_field.?);
                    const path = try self.getCurrentPath();
                    defer self.allocator.free(path);
                    include_this = self.shouldInclude(path);
                    
                    if (!include_this) {
                        // Skip the field name and colon we might have written
                        _ = self.path_stack.pop();
                    }
                }
                
                if (include_this) {
                    // Write comma if needed
                    if (self.getCurrentDepth()) |depth| {
                        if (!self.isInArray() and depth.items_written > 0) {
                            try output.write(",");
                        } else if (self.isInArray() and depth.items_written > 0) {
                            try output.write(",");
                        }
                    }
                    
                    // Write field name if we have one
                    if (self.current_field != null and !self.isInArray()) {
                        try output.write("\"");
                        try output.write(self.current_field.?);
                        try output.write("\":");
                    }
                    
                    try output.writeToken(token, input_data);
                    
                    // Update parent's item count
                    if (self.getCurrentDepth()) |depth| {
                        depth.items_written += 1;
                    }
                }
                
                // Push new depth
                try self.depth_stack.append(.{
                    .is_array = true,
                    .is_included = include_this,
                });
                
                self.current_field = null;
            },
            
            .object_end, .array_end => {
                if (self.depth_stack.items.len > 0) {
                    const depth = self.depth_stack.items[self.depth_stack.items.len - 1];
                    _ = self.depth_stack.pop();
                    
                    if (depth.is_included) {
                        try output.writeToken(token, input_data);
                    }
                    
                    // Pop path if we're exiting an object
                    if (!depth.is_array and self.path_stack.items.len > 0) {
                        _ = self.path_stack.pop();
                    }
                }
            },
            
            .string => {
                if (!self.isInArray() and self.current_field == null and self.isIncluded()) {
                    // This is a field name
                    const field_name = input_data[token.start..token.end];
                    const unquoted = if (field_name.len >= 2 and field_name[0] == '"' and field_name[field_name.len - 1] == '"')
                        field_name[1..field_name.len - 1]
                    else
                        field_name;
                    
                    self.current_field = unquoted;
                } else if (self.isIncluded()) {
                    // This is a value
                    const should_write = blk: {
                        if (self.isInArray()) {
                            break :blk true;
                        } else if (self.current_field != null) {
                            try self.path_stack.append(self.current_field.?);
                            const path = try self.getCurrentPath();
                            defer self.allocator.free(path);
                            const include = self.shouldInclude(path);
                            _ = self.path_stack.pop();
                            break :blk include;
                        }
                        break :blk false;
                    };
                    
                    if (should_write) {
                        // Write comma if needed
                        if (self.getCurrentDepth()) |depth| {
                            if (!self.isInArray() and depth.items_written > 0) {
                                try output.write(",");
                            } else if (self.isInArray() and depth.items_written > 0) {
                                try output.write(",");
                            }
                        }
                        
                        // Write field name if we have one
                        if (self.current_field != null and !self.isInArray()) {
                            try output.write("\"");
                            try output.write(self.current_field.?);
                            try output.write("\":");
                        }
                        
                        try output.writeToken(token, input_data);
                        
                        // Update parent's item count
                        if (self.getCurrentDepth()) |depth| {
                            depth.items_written += 1;
                        }
                    }
                    
                    self.current_field = null;
                }
            },
            
            .number, .boolean_true, .boolean_false, .null => {
                if (self.isIncluded()) {
                    const should_write = blk: {
                        if (self.isInArray()) {
                            break :blk true;
                        } else if (self.current_field != null) {
                            try self.path_stack.append(self.current_field.?);
                            const path = try self.getCurrentPath();
                            defer self.allocator.free(path);
                            const include = self.shouldInclude(path);
                            _ = self.path_stack.pop();
                            break :blk include;
                        }
                        break :blk false;
                    };
                    
                    if (should_write) {
                        // Write comma if needed
                        if (self.getCurrentDepth()) |depth| {
                            if (!self.isInArray() and depth.items_written > 0) {
                                try output.write(",");
                            } else if (self.isInArray() and depth.items_written > 0) {
                                try output.write(",");
                            }
                        }
                        
                        // Write field name if we have one
                        if (self.current_field != null and !self.isInArray()) {
                            try output.write("\"");
                            try output.write(self.current_field.?);
                            try output.write("\":");
                        }
                        
                        try output.writeToken(token, input_data);
                        
                        // Update parent's item count
                        if (self.getCurrentDepth()) |depth| {
                            depth.items_written += 1;
                        }
                    }
                    
                    self.current_field = null;
                }
            },
            
            .colon => {
                // Skip colons - we write them ourselves when needed
            },
            
            .comma => {
                // Skip commas - we handle them ourselves
                self.current_field = null;
            },
            
            .whitespace, .comment => {
                // Skip whitespace and comments
            },
            
            .eof => {
                // End of stream
            },
            
            .parse_error => {
                return error.ParseError;
            },
        }
    }
};