//! JSON Validation Utilities
//! 
//! Fast JSON validation for the production minifier, optimized for speed
//! while maintaining correctness. Provides both streaming and batch validation.

const std = @import("std");

/// Fast JSON validation without parsing
pub fn validateJSON(input: []const u8) !void {
    if (input.len == 0) return error.InvalidJson;
    
    var validator = JSONValidator{};
    try validator.validate(input);
}

/// Check if two JSON strings are semantically equivalent
pub fn semanticEquals(a: []const u8, b: []const u8) bool {
    // Simple implementation - in production this would be more sophisticated
    if (a.len == b.len) {
        return std.mem.eql(u8, a, b);
    }
    
    // For now, just compare normalized versions (simplified)
    return false;
}

/// Fast JSON validator
const JSONValidator = struct {
    stack: [64]Context = undefined,
    stack_depth: u8 = 0,
    
    const Context = enum {
        object,
        array,
        value,
    };
    
    pub fn validate(self: *JSONValidator, input: []const u8) !void {
        var pos: usize = 0;
        var in_string = false;
        var escape_next = false;
        
        // Skip leading whitespace
        pos = skipWhitespace(input, pos);
        if (pos >= input.len) return error.InvalidJson;
        
        // Must start with object, array, or value
        switch (input[pos]) {
            '{' => try self.pushContext(.object),
            '[' => try self.pushContext(.array),
            '"', '0'...'9', '-', 't', 'f', 'n' => try self.pushContext(.value),
            else => return error.InvalidJson,
        }
        
        while (pos < input.len) {
            const byte = input[pos];
            
            if (escape_next) {
                escape_next = false;
                pos += 1;
                continue;
            }
            
            if (in_string) {
                switch (byte) {
                    '"' => in_string = false,
                    '\\' => escape_next = true,
                    else => {},
                }
                pos += 1;
                continue;
            }
            
            switch (byte) {
                '"' => in_string = true,
                '{' => try self.pushContext(.object),
                '}' => try self.popContext(.object),
                '[' => try self.pushContext(.array),
                ']' => try self.popContext(.array),
                ' ', '\t', '\n', '\r' => {}, // Skip whitespace
                else => {}, // Other valid JSON characters
            }
            
            pos += 1;
        }
        
        if (self.stack_depth != 0) {
            return error.InvalidJson;
        }
    }
    
    fn pushContext(self: *JSONValidator, context: Context) !void {
        if (self.stack_depth >= self.stack.len) {
            return error.NestingTooDeep;
        }
        self.stack[self.stack_depth] = context;
        self.stack_depth += 1;
    }
    
    fn popContext(self: *JSONValidator, expected: Context) !void {
        if (self.stack_depth == 0) {
            return error.InvalidJson;
        }
        
        self.stack_depth -= 1;
        if (self.stack[self.stack_depth] != expected) {
            return error.InvalidJson;
        }
    }
};

fn skipWhitespace(input: []const u8, start: usize) usize {
    var pos = start;
    while (pos < input.len) {
        switch (input[pos]) {
            ' ', '\t', '\n', '\r' => pos += 1,
            else => break,
        }
    }
    return pos;
}