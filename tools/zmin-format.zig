//! zmin-format: JSON formatter and pretty printer
//!
//! This tool provides the opposite functionality of zmin - it takes minified
//! JSON and formats it with proper indentation and spacing.

const std = @import("std");

const FormatOptions = struct {
    indent_size: u8 = 2,
    use_tabs: bool = false,
    sort_keys: bool = false,
    ascii_only: bool = false,
    trailing_comma: bool = false,
    quote_style: enum { double, single } = .double,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage(args[0]);
        return;
    }

    var options = FormatOptions{};
    var input_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;

    // Parse arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--indent")) {
            i += 1;
            if (i >= args.len) {
                try std.io.getStdErr().writer().print("--indent requires a value\n", .{});
                return;
            }
            options.indent_size = try std.fmt.parseInt(u8, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--tabs")) {
            options.use_tabs = true;
        } else if (std.mem.eql(u8, arg, "--sort-keys")) {
            options.sort_keys = true;
        } else if (std.mem.eql(u8, arg, "--ascii")) {
            options.ascii_only = true;
        } else if (std.mem.eql(u8, arg, "--trailing-comma")) {
            options.trailing_comma = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage(args[0]);
            return;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            if (input_file == null) {
                input_file = arg;
            } else if (output_file == null) {
                output_file = arg;
            } else {
                try std.io.getStdErr().writer().print("Too many arguments\n", .{});
                return;
            }
        } else {
            try std.io.getStdErr().writer().print("Unknown option: {s}\n", .{arg});
            return;
        }
    }

    // Read input
    const input = if (input_file) |file| blk: {
        if (std.mem.eql(u8, file, "-")) {
            break :blk try std.io.getStdIn().reader().readAllAlloc(allocator, 10 * 1024 * 1024);
        } else {
            break :blk try std.fs.cwd().readFileAlloc(allocator, file, 10 * 1024 * 1024);
        }
    } else blk: {
        break :blk try std.io.getStdIn().reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    };
    defer allocator.free(input);

    // Format JSON
    const formatted = try formatJson(allocator, input, options);
    defer allocator.free(formatted);

    // Write output
    if (output_file) |file| {
        if (std.mem.eql(u8, file, "-")) {
            try std.io.getStdOut().writeAll(formatted);
        } else {
            try std.fs.cwd().writeFile(file, formatted);
        }
    } else {
        try std.io.getStdOut().writeAll(formatted);
    }
}

fn printUsage(program_name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Usage: {s} [OPTIONS] [INPUT] [OUTPUT]
        \\
        \\Format minified JSON with proper indentation
        \\
        \\Options:
        \\  -h, --help           Show this help message
        \\  --indent N           Set indent size (default: 2)
        \\  --tabs               Use tabs for indentation
        \\  --sort-keys          Sort object keys alphabetically
        \\  --ascii              Escape non-ASCII characters
        \\  --trailing-comma     Add trailing commas (non-standard)
        \\
        \\Examples:
        \\  {s} minified.json formatted.json
        \\  echo '{{}}' | {s} --indent 4
        \\  {s} --sort-keys data.json
        \\
    , .{ program_name, program_name, program_name, program_name });
}

fn formatJson(allocator: std.mem.Allocator, input: []const u8, options: FormatOptions) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    var writer = output.writer();

    var parser = JsonParser.init(input);
    try formatValue(&parser, writer, options, 0);

    // Add final newline
    try writer.writeByte('\n');

    return output.toOwnedSlice();
}

const JsonParser = struct {
    input: []const u8,
    pos: usize = 0,

    pub fn init(input: []const u8) JsonParser {
        return .{ .input = input };
    }

    pub fn peek(self: *JsonParser) ?u8 {
        self.skipWhitespace();
        if (self.pos >= self.input.len) return null;
        return self.input[self.pos];
    }

    pub fn consume(self: *JsonParser) !u8 {
        self.skipWhitespace();
        if (self.pos >= self.input.len) return error.UnexpectedEnd;
        const c = self.input[self.pos];
        self.pos += 1;
        return c;
    }

    pub fn consumeString(self: *JsonParser) ![]const u8 {
        const quote = try self.consume();
        if (quote != '"') return error.ExpectedString;

        const start = self.pos;
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            self.pos += 1;

            if (c == '"') {
                return self.input[start .. self.pos - 1];
            } else if (c == '\\') {
                if (self.pos >= self.input.len) return error.UnexpectedEnd;
                self.pos += 1; // Skip escaped character
            }
        }

        return error.UnterminatedString;
    }

    pub fn consumeNumber(self: *JsonParser) ![]const u8 {
        self.skipWhitespace();
        const start = self.pos;

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (!std.ascii.isDigit(c) and c != '-' and c != '+' and
                c != '.' and c != 'e' and c != 'E')
            {
                break;
            }
            self.pos += 1;
        }

        return self.input[start..self.pos];
    }

    pub fn consumeLiteral(self: *JsonParser) ![]const u8 {
        self.skipWhitespace();
        const start = self.pos;

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (!std.ascii.isAlphabetic(c)) break;
            self.pos += 1;
        }

        return self.input[start..self.pos];
    }

    fn skipWhitespace(self: *JsonParser) void {
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c != ' ' and c != '\t' and c != '\n' and c != '\r') break;
            self.pos += 1;
        }
    }
};

fn formatValue(
    parser: *JsonParser,
    writer: anytype,
    options: FormatOptions,
    depth: u32,
) !void {
    const c = parser.peek() orelse return error.UnexpectedEnd;

    switch (c) {
        '{' => try formatObject(parser, writer, options, depth),
        '[' => try formatArray(parser, writer, options, depth),
        '"' => {
            const str = try parser.consumeString();
            try writer.writeByte('"');
            try writeEscapedString(writer, str, options.ascii_only);
            try writer.writeByte('"');
        },
        't', 'f', 'n' => {
            const literal = try parser.consumeLiteral();
            try writer.writeAll(literal);
        },
        else => {
            const number = try parser.consumeNumber();
            try writer.writeAll(number);
        },
    }
}

fn formatObject(
    parser: *JsonParser,
    writer: anytype,
    options: FormatOptions,
    depth: u32,
) !void {
    _ = try parser.consume(); // '{'

    try writer.writeByte('{');

    var first = true;
    while (true) {
        const c = parser.peek() orelse return error.UnexpectedEnd;
        if (c == '}') break;

        if (!first) {
            _ = try parser.consume(); // ','
        }

        // New line and indent
        try writer.writeByte('\n');
        try writeIndent(writer, options, depth + 1);

        // Key
        const key = try parser.consumeString();
        try writer.writeByte('"');
        try writeEscapedString(writer, key, options.ascii_only);
        try writer.writeByte('"');

        _ = try parser.consume(); // ':'
        try writer.writeAll(": ");

        // Value
        try formatValue(parser, writer, options, depth + 1);

        // Check for next item
        const next = parser.peek() orelse return error.UnexpectedEnd;
        if (next == ',') {
            try writer.writeByte(',');
        } else if (next == '}' and options.trailing_comma and !first) {
            try writer.writeByte(',');
        }

        first = false;
    }

    _ = try parser.consume(); // '}'

    if (!first) {
        try writer.writeByte('\n');
        try writeIndent(writer, options, depth);
    }

    try writer.writeByte('}');
}

fn formatArray(
    parser: *JsonParser,
    writer: anytype,
    options: FormatOptions,
    depth: u32,
) !void {
    _ = try parser.consume(); // '['

    try writer.writeByte('[');

    var first = true;
    while (true) {
        const c = parser.peek() orelse return error.UnexpectedEnd;
        if (c == ']') break;

        if (!first) {
            _ = try parser.consume(); // ','
        }

        // New line and indent
        try writer.writeByte('\n');
        try writeIndent(writer, options, depth + 1);

        // Value
        try formatValue(parser, writer, options, depth + 1);

        // Check for next item
        const next = parser.peek() orelse return error.UnexpectedEnd;
        if (next == ',') {
            try writer.writeByte(',');
        } else if (next == ']' and options.trailing_comma and !first) {
            try writer.writeByte(',');
        }

        first = false;
    }

    _ = try parser.consume(); // ']'

    if (!first) {
        try writer.writeByte('\n');
        try writeIndent(writer, options, depth);
    }

    try writer.writeByte(']');
}

fn writeIndent(writer: anytype, options: FormatOptions, depth: u32) !void {
    if (options.use_tabs) {
        for (0..depth) |_| {
            try writer.writeByte('\t');
        }
    } else {
        const spaces = depth * options.indent_size;
        for (0..spaces) |_| {
            try writer.writeByte(' ');
        }
    }
}

fn writeEscapedString(writer: anytype, str: []const u8, ascii_only: bool) !void {
    for (str) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x08 => try writer.writeAll("\\b"),
            0x0C => try writer.writeAll("\\f"),
            else => {
                if (ascii_only and c > 0x7F) {
                    // Escape non-ASCII as Unicode
                    try writer.print("\\u{X:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}
