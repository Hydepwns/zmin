const std = @import("std");
const types = @import("types.zig");

pub fn writeByte(parser: *types.MinifyingParser, byte: u8) !void {
    if (parser.output_pos >= parser.output_buffer.len) {
        try parser.flush();
    }
    parser.output_buffer[parser.output_pos] = byte;
    parser.output_pos += 1;
}

pub fn writeBytes(parser: *types.MinifyingParser, bytes: []const u8) !void {
    if (parser.output_pos + bytes.len >= parser.output_buffer.len) {
        try parser.flush();
        if (bytes.len > parser.output_buffer.len) {
            // Large write, bypass buffer
            try parser.writer.writeAll(bytes);
            return;
        }
    }
    @memcpy(parser.output_buffer[parser.output_pos .. parser.output_pos + bytes.len], bytes);
    parser.output_pos += bytes.len;
}

// Pretty-printing helper functions
pub fn writeIndent(parser: *types.MinifyingParser) !void {
    if (!parser.pretty) return;

    const indent_spaces = parser.indent_level * parser.indent_size;
    var i: usize = 0;
    while (i < indent_spaces) : (i += 1) {
        try writeByte(parser, ' ');
    }
}

pub fn writeNewline(parser: *types.MinifyingParser) !void {
    if (!parser.pretty) return;
    try writeByte(parser, '\n');
    parser.needs_indent = true;
}

pub fn writeIndentIfNeeded(parser: *types.MinifyingParser) !void {
    if (parser.needs_indent) {
        try writeIndent(parser);
        parser.needs_indent = false;
    }
}

pub fn increaseIndent(parser: *types.MinifyingParser) void {
    if (parser.pretty) {
        parser.indent_level += 1;
    }
}

pub fn decreaseIndent(parser: *types.MinifyingParser) void {
    if (parser.pretty and parser.indent_level > 0) {
        parser.indent_level -= 1;
    }
}
