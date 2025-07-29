//! Lightweight JSON Validator
//!
//! This module provides fast JSON validation that can be used by all minifier modes
//! to ensure consistent error handling while maintaining performance characteristics.
//!
//! Key design principles:
//! - Single-pass validation
//! - Minimal memory overhead
//! - Same error types as full MinifyingParser
//! - Optimized for common cases

const std = @import("std");

/// Validation errors that match the MinifyingParser errors
pub const ValidationError = error{
    InvalidObjectKey,
    InvalidValue,
    NestingTooDeep,
    UnexpectedCharacter,
    InvalidEscape,
    InvalidUnicode,
    UnexpectedEndOfInput,
    ParserError,
};

/// Lightweight context tracking for validation
const Context = enum {
    TopLevel,
    Object,
    Array,
};

/// Parser state for validation
const State = enum {
    TopLevel,
    ObjectStart,
    ObjectKey,
    ObjectKeyString,
    ObjectKeyStringEscape,
    ObjectKeyStringEscapeUnicode,
    ObjectColon,
    ObjectValue,
    ObjectComma,
    ArrayStart,
    ArrayValue,
    ArrayComma,
    String,
    StringEscape,
    StringEscapeUnicode,
    Number,
    NumberDecimal,
    NumberExponent,
    NumberExponentSign,
    True,
    False,
    Null,
    Done,
};

/// Lightweight JSON validator
pub const LightweightValidator = struct {
    state: State = .TopLevel,
    count: u32 = 0,
    context_stack: [32]Context = undefined,
    context_depth: u8 = 1,
    string_unicode_codepoint: u21 = 0,
    string_unicode_bytes_remaining: u3 = 0,

    const Self = @This();

    pub fn init() Self {
        var validator = Self{};
        validator.context_stack[0] = .TopLevel;
        return validator;
    }

    /// Validate a complete JSON input
    pub fn validate(input: []const u8) ValidationError!void {
        var validator = init();
        try validator.validateBytes(input);
        try validator.finalize();
    }

    /// Validate bytes incrementally
    pub fn validateBytes(self: *Self, input: []const u8) ValidationError!void {
        for (input) |byte| {
            try self.validateByte(byte);
        }
    }

    /// Finalize validation (check we're in a valid end state)
    pub fn finalize(self: *Self) ValidationError!void {
        switch (self.state) {
            .TopLevel, .Done => return,
            // Numbers, booleans, and null can end at EOF
            .Number, .NumberDecimal, .NumberExponentSign => {
                const context = self.getCurrentContext();
                if (context == .TopLevel) return;
                return ValidationError.UnexpectedEndOfInput;
            },
            .True => {
                if (self.count >= 4) return; // "true" is complete
                return ValidationError.UnexpectedEndOfInput;
            },
            .False => {
                if (self.count >= 5) return; // "false" is complete  
                return ValidationError.UnexpectedEndOfInput;
            },
            .Null => {
                if (self.count >= 4) return; // "null" is complete
                return ValidationError.UnexpectedEndOfInput;
            },
            else => return ValidationError.UnexpectedEndOfInput,
        }
    }

    /// Validate a single byte
    pub fn validateByte(self: *Self, byte: u8) ValidationError!void {
        switch (self.state) {
            .TopLevel => try self.handleTopLevel(byte),
            .ObjectStart => try self.handleObjectStart(byte),
            .ObjectKey => try self.handleObjectKey(byte),
            .ObjectKeyString => try self.handleObjectKeyString(byte),
            .ObjectKeyStringEscape => try self.handleObjectKeyStringEscape(byte),
            .ObjectKeyStringEscapeUnicode => try self.handleObjectKeyStringEscapeUnicode(byte),
            .ObjectColon => try self.handleObjectColon(byte),
            .ObjectValue => try self.handleObjectValue(byte),
            .ObjectComma => try self.handleObjectComma(byte),
            .ArrayStart => try self.handleArrayStart(byte),
            .ArrayValue => try self.handleArrayValue(byte),
            .ArrayComma => try self.handleArrayComma(byte),
            .String => try self.handleString(byte),
            .StringEscape => try self.handleStringEscape(byte),
            .StringEscapeUnicode => try self.handleStringEscapeUnicode(byte),
            .Number => try self.handleNumber(byte),
            .NumberDecimal => try self.handleNumberDecimal(byte),
            .NumberExponent => try self.handleNumberExponent(byte),
            .NumberExponentSign => try self.handleNumberExponentSign(byte),
            .True => try self.handleTrue(byte),
            .False => try self.handleFalse(byte),
            .Null => try self.handleNull(byte),
            .Done => return ValidationError.UnexpectedCharacter,
        }
    }

    fn pushContext(self: *Self, context: Context) ValidationError!void {
        if (self.context_depth >= self.context_stack.len) {
            return ValidationError.NestingTooDeep;
        }
        self.context_stack[self.context_depth] = context;
        self.context_depth += 1;
    }

    fn popContext(self: *Self) ?Context {
        if (self.context_depth == 0) return null;
        self.context_depth -= 1;
        return self.context_stack[self.context_depth];
    }

    fn getCurrentContext(self: *Self) Context {
        if (self.context_depth == 0) return .TopLevel;
        return self.context_stack[self.context_depth - 1];
    }

    fn isWhitespace(byte: u8) bool {
        return switch (byte) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }

    fn isHexDigit(byte: u8) bool {
        return switch (byte) {
            '0'...'9', 'A'...'F', 'a'...'f' => true,
            else => false,
        };
    }

    // State handlers (simplified versions of the full parser)
    fn handleTopLevel(self: *Self, byte: u8) ValidationError!void {
        if (isWhitespace(byte)) return;

        switch (byte) {
            '{' => {
                try self.pushContext(.Object);
                self.state = .ObjectStart;
            },
            '[' => {
                try self.pushContext(.Array);
                self.state = .ArrayStart;
            },
            '"' => self.state = .String,
            't' => {
                self.state = .True;
                self.count = 1;
            },
            'f' => {
                self.state = .False;
                self.count = 1;
            },
            'n' => {
                self.state = .Null;
                self.count = 1;
            },
            '-', '0'...'9' => self.state = .Number,
            else => return ValidationError.UnexpectedCharacter,
        }
    }

    fn handleObjectStart(self: *Self, byte: u8) ValidationError!void {
        if (isWhitespace(byte)) return;

        switch (byte) {
            '}' => {
                _ = self.popContext();
                const context = self.getCurrentContext();
                switch (context) {
                    .Object => self.state = .ObjectComma,
                    .Array => self.state = .ArrayComma,
                    .TopLevel => self.state = .Done,
                }
            },
            '"' => self.state = .ObjectKeyString,
            else => return ValidationError.InvalidObjectKey,
        }
    }

    fn handleObjectKey(self: *Self, byte: u8) ValidationError!void {
        if (isWhitespace(byte)) return;

        switch (byte) {
            '"' => self.state = .ObjectKeyString,
            else => return ValidationError.InvalidObjectKey,
        }
    }

    fn handleObjectKeyString(self: *Self, byte: u8) ValidationError!void {
        switch (byte) {
            '"' => self.state = .ObjectColon,
            '\\' => self.state = .ObjectKeyStringEscape,
            0x00...0x1F => return ValidationError.UnexpectedCharacter,
            else => {},
        }
    }

    fn handleObjectKeyStringEscape(self: *Self, byte: u8) ValidationError!void {
        switch (byte) {
            '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => self.state = .ObjectKeyString,
            'u' => {
                self.state = .ObjectKeyStringEscapeUnicode;
                self.count = 0;
            },
            else => return ValidationError.InvalidEscape,
        }
    }

    fn handleObjectKeyStringEscapeUnicode(self: *Self, byte: u8) ValidationError!void {
        if (!isHexDigit(byte)) return ValidationError.InvalidUnicode;
        
        self.count += 1;
        if (self.count >= 4) {
            self.state = .ObjectKeyString;
        }
    }

    fn handleObjectColon(self: *Self, byte: u8) ValidationError!void {
        if (isWhitespace(byte)) return;

        switch (byte) {
            ':' => self.state = .ObjectValue,
            else => return ValidationError.UnexpectedCharacter,
        }
    }

    fn handleObjectValue(self: *Self, byte: u8) ValidationError!void {
        if (isWhitespace(byte)) return;

        switch (byte) {
            '{' => {
                try self.pushContext(.Object);
                self.state = .ObjectStart;
            },
            '[' => {
                try self.pushContext(.Array);
                self.state = .ArrayStart;
            },
            '"' => self.state = .String,
            't' => {
                self.state = .True;
                self.count = 1;
            },
            'f' => {
                self.state = .False;
                self.count = 1;
            },
            'n' => {
                self.state = .Null;
                self.count = 1;
            },
            '-', '0'...'9' => self.state = .Number,
            else => return ValidationError.InvalidValue,
        }
    }

    fn handleObjectComma(self: *Self, byte: u8) ValidationError!void {
        if (isWhitespace(byte)) return;

        switch (byte) {
            ',' => self.state = .ObjectKey,
            '}' => {
                _ = self.popContext();
                const context = self.getCurrentContext();
                switch (context) {
                    .Object => self.state = .ObjectComma,
                    .Array => self.state = .ArrayComma,
                    .TopLevel => self.state = .Done,
                }
            },
            else => return ValidationError.UnexpectedCharacter,
        }
    }

    fn handleArrayStart(self: *Self, byte: u8) ValidationError!void {
        if (isWhitespace(byte)) return;

        switch (byte) {
            ']' => {
                _ = self.popContext();
                const context = self.getCurrentContext();
                switch (context) {
                    .Object => self.state = .ObjectComma,
                    .Array => self.state = .ArrayComma,
                    .TopLevel => self.state = .Done,
                }
            },
            '{' => {
                try self.pushContext(.Object);
                self.state = .ObjectStart;
            },
            '[' => {
                try self.pushContext(.Array);
                self.state = .ArrayStart;
            },
            '"' => self.state = .String,
            't' => {
                self.state = .True;
                self.count = 1;
            },
            'f' => {
                self.state = .False;
                self.count = 1;
            },
            'n' => {
                self.state = .Null;
                self.count = 1;
            },
            '-', '0'...'9' => self.state = .Number,
            else => return ValidationError.InvalidValue,
        }
    }

    fn handleArrayValue(self: *Self, byte: u8) ValidationError!void {
        if (isWhitespace(byte)) return;

        switch (byte) {
            '{' => {
                try self.pushContext(.Object);
                self.state = .ObjectStart;
            },
            '[' => {
                try self.pushContext(.Array);
                self.state = .ArrayStart;
            },
            '"' => self.state = .String,
            't' => {
                self.state = .True;
                self.count = 1;
            },
            'f' => {
                self.state = .False;
                self.count = 1;
            },
            'n' => {
                self.state = .Null;
                self.count = 1;
            },
            '-', '0'...'9' => self.state = .Number,
            else => return ValidationError.InvalidValue,
        }
    }

    fn handleArrayComma(self: *Self, byte: u8) ValidationError!void {
        if (isWhitespace(byte)) return;

        switch (byte) {
            ',' => self.state = .ArrayValue,
            ']' => {
                _ = self.popContext();
                const context = self.getCurrentContext();
                switch (context) {
                    .Object => self.state = .ObjectComma,
                    .Array => self.state = .ArrayComma,
                    .TopLevel => self.state = .Done,
                }
            },
            else => return ValidationError.UnexpectedCharacter,
        }
    }

    fn handleString(self: *Self, byte: u8) ValidationError!void {
        switch (byte) {
            '"' => {
                const context = self.getCurrentContext();
                switch (context) {
                    .Object => self.state = .ObjectComma,
                    .Array => self.state = .ArrayComma,
                    .TopLevel => self.state = .Done,
                }
            },
            '\\' => self.state = .StringEscape,
            0x00...0x1F => return ValidationError.UnexpectedCharacter,
            else => {},
        }
    }

    fn handleStringEscape(self: *Self, byte: u8) ValidationError!void {
        switch (byte) {
            '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => self.state = .String,
            'u' => {
                self.state = .StringEscapeUnicode;
                self.count = 0;
            },
            else => return ValidationError.InvalidEscape,
        }
    }

    fn handleStringEscapeUnicode(self: *Self, byte: u8) ValidationError!void {
        if (!isHexDigit(byte)) return ValidationError.InvalidUnicode;
        
        self.count += 1;
        if (self.count >= 4) {
            self.state = .String;
        }
    }

    fn handleNumber(self: *Self, byte: u8) ValidationError!void {
        switch (byte) {
            '0'...'9' => {},
            '.' => self.state = .NumberDecimal,
            'e', 'E' => self.state = .NumberExponent,
            else => {
                // End of number, transition based on context
                const context = self.getCurrentContext();
                switch (context) {
                    .Object => self.state = .ObjectComma,
                    .Array => self.state = .ArrayComma,
                    .TopLevel => self.state = .Done,
                }
                // Re-process this byte in the new state
                try self.validateByte(byte);
            },
        }
    }

    fn handleNumberDecimal(self: *Self, byte: u8) ValidationError!void {
        switch (byte) {
            '0'...'9' => {},
            'e', 'E' => self.state = .NumberExponent,
            else => {
                const context = self.getCurrentContext();
                switch (context) {
                    .Object => self.state = .ObjectComma,
                    .Array => self.state = .ArrayComma,
                    .TopLevel => self.state = .Done,
                }
                try self.validateByte(byte);
            },
        }
    }

    fn handleNumberExponent(self: *Self, byte: u8) ValidationError!void {
        switch (byte) {
            '+', '-' => self.state = .NumberExponentSign,
            '0'...'9' => self.state = .NumberExponentSign,
            else => return ValidationError.UnexpectedCharacter,
        }
    }

    fn handleNumberExponentSign(self: *Self, byte: u8) ValidationError!void {
        switch (byte) {
            '0'...'9' => {},
            else => {
                const context = self.getCurrentContext();
                switch (context) {
                    .Object => self.state = .ObjectComma,
                    .Array => self.state = .ArrayComma,
                    .TopLevel => self.state = .Done,
                }
                try self.validateByte(byte);
            },
        }
    }

    fn handleTrue(self: *Self, byte: u8) ValidationError!void {
        const expected = "true";
        if (self.count >= expected.len or byte != expected[self.count]) {
            return ValidationError.UnexpectedCharacter;
        }
        
        self.count += 1;
        if (self.count >= expected.len) {
            const context = self.getCurrentContext();
            switch (context) {
                .Object => self.state = .ObjectComma,
                .Array => self.state = .ArrayComma,
                .TopLevel => self.state = .Done,
            }
        }
    }

    fn handleFalse(self: *Self, byte: u8) ValidationError!void {
        const expected = "false";
        if (self.count >= expected.len or byte != expected[self.count]) {
            return ValidationError.UnexpectedCharacter;
        }
        
        self.count += 1;
        if (self.count >= expected.len) {
            const context = self.getCurrentContext();
            switch (context) {
                .Object => self.state = .ObjectComma,
                .Array => self.state = .ArrayComma,
                .TopLevel => self.state = .Done,
            }
        }
    }

    fn handleNull(self: *Self, byte: u8) ValidationError!void {
        const expected = "null";
        if (self.count >= expected.len or byte != expected[self.count]) {
            return ValidationError.UnexpectedCharacter;
        }
        
        self.count += 1;
        if (self.count >= expected.len) {
            const context = self.getCurrentContext();
            switch (context) {
                .Object => self.state = .ObjectComma,
                .Array => self.state = .ArrayComma,
                .TopLevel => self.state = .Done,
            }
        }
    }
};