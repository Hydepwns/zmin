const std = @import("std");

pub const Context = enum {
    Object,
    Array,
    TopLevel,
};

// State machine for JSON parsing
pub const State = enum {
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
    Error,
};

pub const MinifyingParser = struct {
    // Core streaming parser state
    state: State,
    count: u32,
    string_unicode_codepoint: u21,
    string_unicode_bytes_remaining: u3,

    // Context tracking
    context_stack: [32]Context,
    context_depth: u8,

    // Output buffer management
    output_buffer: []u8,
    output_pos: usize,
    writer: std.io.AnyWriter,

    // Pretty-printing support
    pretty: bool,
    indent_size: u8,
    indent_level: u8,
    needs_indent: bool,

    // Performance tracking
    bytes_processed: u64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter) !Self {
        var parser = Self{
            .state = .TopLevel,
            .count = 0,
            .string_unicode_codepoint = 0,
            .string_unicode_bytes_remaining = 0,
            .context_stack = undefined,
            .context_depth = 0,
            .output_buffer = try allocator.alloc(u8, 64 * 1024), // 64KB buffer
            .output_pos = 0,
            .writer = writer,
            .pretty = false,
            .indent_size = 2,
            .indent_level = 0,
            .needs_indent = false,
            .bytes_processed = 0,
        };
        parser.context_stack[0] = .TopLevel;
        parser.context_depth = 1;
        return parser;
    }

    pub fn initPretty(allocator: std.mem.Allocator, writer: std.io.AnyWriter, indent_size: u8) !Self {
        var parser = Self{
            .state = .TopLevel,
            .count = 0,
            .string_unicode_codepoint = 0,
            .string_unicode_bytes_remaining = 0,
            .context_stack = undefined,
            .context_depth = 0,
            .output_buffer = try allocator.alloc(u8, 64 * 1024), // 64KB buffer
            .output_pos = 0,
            .writer = writer,
            .pretty = true,
            .indent_size = indent_size,
            .indent_level = 0,
            .needs_indent = false,
            .bytes_processed = 0,
        };
        parser.context_stack[0] = .TopLevel;
        parser.context_depth = 1;
        return parser;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.output_buffer);
    }

    pub fn feed(self: *Self, input: []const u8) !void {
        var i: usize = 0;
        while (i < input.len) {
            const byte = input[i];
            try self.feedByte(byte);
            i += 1;
            self.bytes_processed += 1;
        }
    }

    pub fn flush(self: *Self) !void {
        if (self.output_pos > 0) {
            try self.writer.writeAll(self.output_buffer[0..self.output_pos]);
            self.output_pos = 0;
        }
    }

    pub fn feedByte(self: *Self, byte: u8) !void {
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
            .Error => return error.ParserError,
        }
    }

    pub fn pushContext(self: *Self, context: Context) !void {
        if (self.context_depth >= self.context_stack.len) {
            return error.NestingTooDeep;
        }
        self.context_stack[self.context_depth] = context;
        self.context_depth += 1;
    }

    pub fn popContext(self: *Self) ?Context {
        if (self.context_depth == 0) return null;
        self.context_depth -= 1;
        return self.context_stack[self.context_depth];
    }

    pub fn getCurrentContext(self: *Self) Context {
        if (self.context_depth == 0) return .TopLevel;
        return self.context_stack[self.context_depth - 1];
    }

    // These will be implemented in other modules
    fn handleTopLevel(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleTopLevel(self, byte);
    }
    fn handleObjectStart(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleObjectStart(self, byte);
    }
    fn handleObjectKey(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleObjectKey(self, byte);
    }
    fn handleObjectKeyString(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleObjectKeyString(self, byte);
    }
    fn handleObjectKeyStringEscape(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleObjectKeyStringEscape(self, byte);
    }
    fn handleObjectKeyStringEscapeUnicode(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleObjectKeyStringEscapeUnicode(self, byte);
    }
    fn handleObjectColon(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleObjectColon(self, byte);
    }
    fn handleObjectValue(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleObjectValue(self, byte);
    }
    fn handleObjectComma(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleObjectComma(self, byte);
    }
    fn handleArrayStart(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleArrayStart(self, byte);
    }
    fn handleArrayValue(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleArrayValue(self, byte);
    }
    fn handleArrayComma(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleArrayComma(self, byte);
    }
    fn handleString(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleString(self, byte);
    }
    fn handleStringEscape(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleStringEscape(self, byte);
    }
    fn handleStringEscapeUnicode(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleStringEscapeUnicode(self, byte);
    }
    fn handleNumber(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleNumber(self, byte);
    }
    fn handleNumberDecimal(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleNumberDecimal(self, byte);
    }
    fn handleNumberExponent(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleNumberExponent(self, byte);
    }
    fn handleNumberExponentSign(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleNumberExponentSign(self, byte);
    }
    fn handleTrue(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleTrue(self, byte);
    }
    fn handleFalse(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleFalse(self, byte);
    }
    fn handleNull(self: *Self, byte: u8) !void {
        const handlers = @import("handlers.zig");
        try handlers.handleNull(self, byte);
    }
};
