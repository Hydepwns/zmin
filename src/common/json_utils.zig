//! Common JSON Validation and Processing Utilities
//!
//! This module consolidates JSON validation logic and common patterns
//! used throughout the codebase.

const std = @import("std");
const constants = @import("constants.zig");
const errors = @import("../core/errors.zig");

/// JSON token types
pub const TokenType = enum {
    object_start,     // {
    object_end,       // }
    array_start,      // [
    array_end,        // ]
    string,           // "..."
    number,           // 123, -45.67
    boolean_true,     // true
    boolean_false,    // false
    null_value,       // null
    comma,            // ,
    colon,            // :
    whitespace,       // space, tab, newline, carriage return
    eof,              // end of file
    
    pub fn isValue(self: TokenType) bool {
        return switch (self) {
            .string, .number, .boolean_true, .boolean_false, .null_value => true,
            else => false,
        };
    }
    
    pub fn isContainer(self: TokenType) bool {
        return self == .object_start or self == .array_start;
    }
};

/// JSON validation state
pub const ValidationState = struct {
    /// Current nesting depth
    depth: u32 = 0,
    
    /// Stack of container types
    container_stack: std.BoundedArray(ContainerType, constants.Json.MAX_DEPTH) = .{},
    
    /// Expected tokens based on current state
    expected_tokens: TokenSet = TokenSet.initFull(),
    
    /// Line number for error reporting
    line: u32 = 1,
    
    /// Column number for error reporting
    column: u32 = 1,
    
    /// Whether we're in a string
    in_string: bool = false,
    
    /// Whether we're in an escape sequence
    in_escape: bool = false,
    
    /// Unicode escape buffer
    unicode_buffer: [4]u8 = undefined,
    unicode_count: u8 = 0,
    
    const ContainerType = enum { object, array };
    
    /// Update position tracking
    pub fn updatePosition(self: *ValidationState, char: u8) void {
        if (char == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
    }
    
    /// Push container onto stack
    pub fn pushContainer(self: *ValidationState, container: ContainerType) !void {
        if (self.depth >= constants.Json.MAX_DEPTH) {
            return error.DepthLimitExceeded;
        }
        
        try self.container_stack.append(container);
        self.depth += 1;
    }
    
    /// Pop container from stack
    pub fn popContainer(self: *ValidationState, expected: ContainerType) !void {
        if (self.container_stack.len == 0) {
            return error.UnexpectedClosing;
        }
        
        const actual = self.container_stack.pop();
        if (actual != expected) {
            return error.MismatchedBrackets;
        }
        
        self.depth -= 1;
    }
    
    /// Get current container type
    pub fn currentContainer(self: *ValidationState) ?ContainerType {
        if (self.container_stack.len == 0) return null;
        return self.container_stack.get(self.container_stack.len - 1);
    }
    
    /// Create error context
    pub fn createError(self: *ValidationState, err: anyerror, details: []const u8) errors.ErrorContext {
        return errors.ErrorContext.init(err, .errors, "JSON validation")
            .withLocation("input", self.line, self.column)
            .withDetails(details);
    }
};

/// Set of expected tokens
pub const TokenSet = std.bit_set.IntegerBitSet(16);

/// Character classification
pub const CharClass = struct {
    /// Check if character is whitespace
    pub inline fn isWhitespace(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }
    
    /// Check if character is a digit
    pub inline fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }
    
    /// Check if character is a hex digit
    pub inline fn isHexDigit(c: u8) bool {
        return isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
    }
    
    /// Check if character can start a number
    pub inline fn isNumberStart(c: u8) bool {
        return isDigit(c) or c == '-';
    }
    
    /// Check if character is a control character
    pub inline fn isControl(c: u8) bool {
        return c < 0x20;
    }
    
    /// Get escape character value
    pub inline fn getEscapeValue(c: u8) ?u8 {
        return switch (c) {
            '"' => '"',
            '\\' => '\\',
            '/' => '/',
            'b' => 0x08,
            'f' => 0x0C,
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            else => null,
        };
    }
};

/// Skip whitespace in buffer
pub fn skipWhitespace(buffer: []const u8, pos: *usize) void {
    while (pos.* < buffer.len and CharClass.isWhitespace(buffer[pos.*])) {
        pos.* += 1;
    }
}

/// Skip whitespace and track position
pub fn skipWhitespaceTracked(buffer: []const u8, pos: *usize, state: *ValidationState) void {
    while (pos.* < buffer.len and CharClass.isWhitespace(buffer[pos.*])) {
        state.updatePosition(buffer[pos.*]);
        pos.* += 1;
    }
}

/// Validate a complete JSON document
pub fn validateJson(input: []const u8) !void {
    var state = ValidationState{};
    var pos: usize = 0;
    
    // Skip initial whitespace
    skipWhitespaceTracked(input, &pos, &state);
    
    // Empty input is invalid
    if (pos >= input.len) {
        return error.UnexpectedEndOfInput;
    }
    
    // Parse one value
    try validateValue(input, &pos, &state);
    
    // Skip trailing whitespace
    skipWhitespaceTracked(input, &pos, &state);
    
    // Should be at end of input
    if (pos < input.len) {
        return error.TrailingData;
    }
    
    // All containers should be closed
    if (state.depth > 0) {
        return error.UnterminatedContainer;
    }
}

/// Validate a JSON value
fn validateValue(input: []const u8, pos: *usize, state: *ValidationState) !void {
    if (pos.* >= input.len) {
        return error.UnexpectedEndOfInput;
    }
    
    const c = input[pos.*];
    
    switch (c) {
        '{' => try validateObject(input, pos, state),
        '[' => try validateArray(input, pos, state),
        '"' => try validateString(input, pos, state),
        't' => try validateLiteral(input, pos, state, "true"),
        'f' => try validateLiteral(input, pos, state, "false"),
        'n' => try validateLiteral(input, pos, state, "null"),
        '-', '0'...'9' => try validateNumber(input, pos, state),
        else => return error.InvalidCharacter,
    }
}

/// Validate object
fn validateObject(input: []const u8, pos: *usize, state: *ValidationState) !void {
    pos.* += 1; // Skip '{'
    state.updatePosition('{');
    try state.pushContainer(.object);
    
    skipWhitespaceTracked(input, pos, state);
    
    // Empty object
    if (pos.* < input.len and input[pos.*] == '}') {
        pos.* += 1;
        state.updatePosition('}');
        try state.popContainer(.object);
        return;
    }
    
    while (true) {
        // Expect string key
        if (pos.* >= input.len or input[pos.*] != '"') {
            return error.ExpectedString;
        }
        
        try validateString(input, pos, state);
        skipWhitespaceTracked(input, pos, state);
        
        // Expect colon
        if (pos.* >= input.len or input[pos.*] != ':') {
            return error.ExpectedColon;
        }
        pos.* += 1;
        state.updatePosition(':');
        skipWhitespaceTracked(input, pos, state);
        
        // Expect value
        try validateValue(input, pos, state);
        skipWhitespaceTracked(input, pos, state);
        
        if (pos.* >= input.len) {
            return error.UnterminatedObject;
        }
        
        // Check for comma or closing brace
        switch (input[pos.*]) {
            ',' => {
                pos.* += 1;
                state.updatePosition(',');
                skipWhitespaceTracked(input, pos, state);
                
                // Check for trailing comma
                if (pos.* < input.len and input[pos.*] == '}') {
                    return error.TrailingComma;
                }
            },
            '}' => {
                pos.* += 1;
                state.updatePosition('}');
                try state.popContainer(.object);
                return;
            },
            else => return error.ExpectedCommaOrCloseBrace,
        }
    }
}

/// Validate array
fn validateArray(input: []const u8, pos: *usize, state: *ValidationState) !void {
    pos.* += 1; // Skip '['
    state.updatePosition('[');
    try state.pushContainer(.array);
    
    skipWhitespaceTracked(input, pos, state);
    
    // Empty array
    if (pos.* < input.len and input[pos.*] == ']') {
        pos.* += 1;
        state.updatePosition(']');
        try state.popContainer(.array);
        return;
    }
    
    while (true) {
        // Expect value
        try validateValue(input, pos, state);
        skipWhitespaceTracked(input, pos, state);
        
        if (pos.* >= input.len) {
            return error.UnterminatedArray;
        }
        
        // Check for comma or closing bracket
        switch (input[pos.*]) {
            ',' => {
                pos.* += 1;
                state.updatePosition(',');
                skipWhitespaceTracked(input, pos, state);
                
                // Check for trailing comma
                if (pos.* < input.len and input[pos.*] == ']') {
                    return error.TrailingComma;
                }
            },
            ']' => {
                pos.* += 1;
                state.updatePosition(']');
                try state.popContainer(.array);
                return;
            },
            else => return error.ExpectedCommaOrCloseBracket,
        }
    }
}

/// Validate string
fn validateString(input: []const u8, pos: *usize, state: *ValidationState) !void {
    pos.* += 1; // Skip opening quote
    state.updatePosition('"');
    
    while (pos.* < input.len) {
        const c = input[pos.*];
        
        if (state.in_escape) {
            if (c == 'u') {
                // Unicode escape
                pos.* += 1;
                state.updatePosition('u');
                
                for (0..4) |_| {
                    if (pos.* >= input.len or !CharClass.isHexDigit(input[pos.*])) {
                        return error.InvalidUnicodeEscape;
                    }
                    pos.* += 1;
                    state.updatePosition(input[pos.* - 1]);
                }
            } else if (CharClass.getEscapeValue(c) == null) {
                return error.InvalidEscapeSequence;
            } else {
                pos.* += 1;
                state.updatePosition(c);
            }
            state.in_escape = false;
        } else {
            switch (c) {
                '"' => {
                    pos.* += 1;
                    state.updatePosition('"');
                    return;
                },
                '\\' => {
                    state.in_escape = true;
                    pos.* += 1;
                    state.updatePosition('\\');
                },
                else => {
                    if (CharClass.isControl(c)) {
                        return error.UnescapedControlCharacter;
                    }
                    pos.* += 1;
                    state.updatePosition(c);
                },
            }
        }
    }
    
    return error.UnterminatedString;
}

/// Validate number
fn validateNumber(input: []const u8, pos: *usize, state: *ValidationState) !void {
    const start = pos.*;
    
    // Optional minus
    if (pos.* < input.len and input[pos.*] == '-') {
        pos.* += 1;
    }
    
    // Integer part
    if (pos.* >= input.len or !CharClass.isDigit(input[pos.*])) {
        return error.InvalidNumber;
    }
    
    if (input[pos.*] == '0') {
        pos.* += 1;
    } else {
        while (pos.* < input.len and CharClass.isDigit(input[pos.*])) {
            pos.* += 1;
        }
    }
    
    // Fractional part
    if (pos.* < input.len and input[pos.*] == '.') {
        pos.* += 1;
        
        if (pos.* >= input.len or !CharClass.isDigit(input[pos.*])) {
            return error.InvalidNumber;
        }
        
        while (pos.* < input.len and CharClass.isDigit(input[pos.*])) {
            pos.* += 1;
        }
    }
    
    // Exponent part
    if (pos.* < input.len and (input[pos.*] == 'e' or input[pos.*] == 'E')) {
        pos.* += 1;
        
        if (pos.* < input.len and (input[pos.*] == '+' or input[pos.*] == '-')) {
            pos.* += 1;
        }
        
        if (pos.* >= input.len or !CharClass.isDigit(input[pos.*])) {
            return error.InvalidNumber;
        }
        
        while (pos.* < input.len and CharClass.isDigit(input[pos.*])) {
            pos.* += 1;
        }
    }
    
    // Update position tracking
    for (input[start..pos.*]) |c| {
        state.updatePosition(c);
    }
}

/// Validate literal (true, false, null)
fn validateLiteral(input: []const u8, pos: *usize, state: *ValidationState, literal: []const u8) !void {
    if (pos.* + literal.len > input.len) {
        return error.UnexpectedEndOfInput;
    }
    
    if (!std.mem.eql(u8, input[pos..pos.* + literal.len], literal)) {
        return error.InvalidLiteral;
    }
    
    pos.* += literal.len;
    for (literal) |c| {
        state.updatePosition(c);
    }
}

/// Fast validation using SIMD (when available)
pub fn validateJsonFast(input: []const u8) !void {
    // For now, fall back to regular validation
    // TODO: Implement SIMD-accelerated validation
    return validateJson(input);
}

/// Extract string value (unescaped)
pub fn extractString(input: []const u8, start: usize, allocator: std.mem.Allocator) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    
    var pos = start + 1; // Skip opening quote
    var in_escape = false;
    
    while (pos < input.len) {
        const c = input[pos];
        
        if (in_escape) {
            if (c == 'u') {
                // Unicode escape
                if (pos + 4 >= input.len) return error.InvalidUnicodeEscape;
                
                const code = std.fmt.parseInt(u16, input[pos + 1..pos + 5], 16) catch {
                    return error.InvalidUnicodeEscape;
                };
                
                // Encode UTF-8
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(code, &buf) catch {
                    return error.InvalidUnicode;
                };
                try result.appendSlice(buf[0..len]);
                
                pos += 5;
            } else {
                const escaped = CharClass.getEscapeValue(c) orelse return error.InvalidEscapeSequence;
                try result.append(escaped);
                pos += 1;
            }
            in_escape = false;
        } else {
            switch (c) {
                '"' => break,
                '\\' => {
                    in_escape = true;
                    pos += 1;
                },
                else => {
                    try result.append(c);
                    pos += 1;
                },
            }
        }
    }
    
    return result.toOwnedSlice();
}

// Tests
test "JSON validation - valid inputs" {
    const valid_inputs = [_][]const u8{
        "{}",
        "[]",
        "null",
        "true",
        "false",
        "0",
        "123",
        "-456",
        "3.14",
        "1e10",
        "\"hello\"",
        "[1,2,3]",
        "{\"key\":\"value\"}",
        "[{\"nested\":true}]",
    };
    
    for (valid_inputs) |input| {
        try validateJson(input);
    }
}

test "JSON validation - invalid inputs" {
    const invalid_inputs = [_][]const u8{
        "",
        "{",
        "}",
        "[",
        "]",
        "{]",
        "[}",
        "{,}",
        "[,]",
        "[1,]",
        "{'key':1}",
        "{key:1}",
        "undefined",
        "NaN",
        "Infinity",
    };
    
    for (invalid_inputs) |input| {
        const result = validateJson(input);
        try std.testing.expect(std.meta.isError(result));
    }
}