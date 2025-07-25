const std = @import("std");
const types = @import("types.zig");
const utils = @import("utils.zig");
const pretty = @import("pretty.zig");

pub fn handleTopLevel(parser: *types.MinifyingParser, byte: u8) !void {
    if (utils.isWhitespace(byte)) return;

    switch (byte) {
        '{' => {
            try pretty.writeByte(parser, byte);
            try parser.pushContext(types.Context.Object);
            pretty.increaseIndent(parser);
            try pretty.writeNewline(parser);
            parser.state = types.State.ObjectStart;
        },
        '[' => {
            try pretty.writeByte(parser, byte);
            try parser.pushContext(types.Context.Array);
            pretty.increaseIndent(parser);
            try pretty.writeNewline(parser);
            parser.state = types.State.ArrayStart;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidTopLevel;
        },
    }
}

pub fn handleObjectStart(parser: *types.MinifyingParser, byte: u8) !void {
    if (utils.isWhitespace(byte)) return;

    switch (byte) {
        '}' => {
            pretty.decreaseIndent(parser);
            try pretty.writeNewline(parser);
            try pretty.writeIndentIfNeeded(parser);
            try pretty.writeByte(parser, byte);
            _ = parser.popContext();
            const context = parser.getCurrentContext();
            switch (context) {
                .Object => parser.state = types.State.ObjectComma,
                .Array => parser.state = types.State.ArrayComma,
                .TopLevel => parser.state = types.State.TopLevel,
            }
        },
        '"' => {
            try pretty.writeIndentIfNeeded(parser);
            try pretty.writeByte(parser, byte);
            parser.state = types.State.ObjectKeyString;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidObjectKey;
        },
    }
}

pub fn handleObjectKey(parser: *types.MinifyingParser, byte: u8) !void {
    if (utils.isWhitespace(byte)) return;

    switch (byte) {
        '"' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.ObjectKeyString;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidObjectKey;
        },
    }
}

pub fn handleObjectKeyString(parser: *types.MinifyingParser, byte: u8) !void {
    switch (byte) {
        '"' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.ObjectColon;
        },
        '\\' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.ObjectKeyStringEscape;
        },
        else => try pretty.writeByte(parser, byte),
    }
}

pub fn handleObjectKeyStringEscape(parser: *types.MinifyingParser, byte: u8) !void {
    switch (byte) {
        '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.ObjectKeyString;
        },
        'u' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.ObjectKeyStringEscapeUnicode;
            parser.string_unicode_bytes_remaining = 4;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidEscapeSequence;
        },
    }
}

pub fn handleObjectKeyStringEscapeUnicode(parser: *types.MinifyingParser, byte: u8) !void {
    if (utils.isHexDigit(byte)) {
        try pretty.writeByte(parser, byte);
        parser.string_unicode_bytes_remaining -= 1;
        if (parser.string_unicode_bytes_remaining == 0) {
            parser.state = types.State.ObjectKeyString;
        }
    } else {
        parser.state = types.State.Error;
        return error.InvalidUnicodeEscape;
    }
}

pub fn handleObjectColon(parser: *types.MinifyingParser, byte: u8) !void {
    if (utils.isWhitespace(byte)) return;

    switch (byte) {
        ':' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.ObjectValue;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidObjectSeparator;
        },
    }
}

pub fn handleObjectValue(parser: *types.MinifyingParser, byte: u8) !void {
    if (utils.isWhitespace(byte)) return;

    switch (byte) {
        '"' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.String;
        },
        '{' => {
            try pretty.writeByte(parser, byte);
            try parser.pushContext(types.Context.Object);
            pretty.increaseIndent(parser);
            try pretty.writeNewline(parser);
            parser.state = types.State.ObjectStart;
        },
        '[' => {
            try pretty.writeByte(parser, byte);
            try parser.pushContext(types.Context.Array);
            pretty.increaseIndent(parser);
            try pretty.writeNewline(parser);
            parser.state = types.State.ArrayStart;
        },
        't' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.True;
        },
        'f' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.False;
        },
        'n' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.Null;
        },
        '-', '0'...'9' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.Number;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidValue;
        },
    }
}

pub fn handleObjectComma(parser: *types.MinifyingParser, byte: u8) !void {
    if (utils.isWhitespace(byte)) return;

    switch (byte) {
        ',' => {
            try pretty.writeByte(parser, byte);
            try pretty.writeNewline(parser);
            parser.state = types.State.ObjectKey;
        },
        '}' => {
            pretty.decreaseIndent(parser);
            try pretty.writeNewline(parser);
            try pretty.writeIndentIfNeeded(parser);
            try pretty.writeByte(parser, byte);
            _ = parser.popContext();
            const context = parser.getCurrentContext();
            switch (context) {
                .Object => parser.state = types.State.ObjectComma,
                .Array => parser.state = types.State.ArrayComma,
                .TopLevel => parser.state = types.State.TopLevel,
            }
        },
        else => {
            parser.state = types.State.Error;
            return error.UnexpectedCharacter;
        },
    }
}

pub fn handleArrayStart(parser: *types.MinifyingParser, byte: u8) !void {
    if (utils.isWhitespace(byte)) return;

    switch (byte) {
        ']' => {
            pretty.decreaseIndent(parser);
            try pretty.writeNewline(parser);
            try pretty.writeIndentIfNeeded(parser);
            try pretty.writeByte(parser, byte);
            _ = parser.popContext();
            const context = parser.getCurrentContext();
            switch (context) {
                .Object => parser.state = types.State.ObjectComma,
                .Array => parser.state = types.State.ArrayComma,
                .TopLevel => parser.state = types.State.TopLevel,
            }
        },
        else => {
            try pretty.writeIndentIfNeeded(parser);
            parser.state = types.State.ArrayValue;
            try handleArrayValue(parser, byte);
        },
    }
}

pub fn handleArrayValue(parser: *types.MinifyingParser, byte: u8) !void {
    if (utils.isWhitespace(byte)) return;

    switch (byte) {
        '"' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.String;
        },
        '{' => {
            try pretty.writeByte(parser, byte);
            try parser.pushContext(types.Context.Object);
            pretty.increaseIndent(parser);
            try pretty.writeNewline(parser);
            parser.state = types.State.ObjectStart;
        },
        '[' => {
            try pretty.writeByte(parser, byte);
            try parser.pushContext(types.Context.Array);
            pretty.increaseIndent(parser);
            try pretty.writeNewline(parser);
            parser.state = types.State.ArrayStart;
        },
        't' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.True;
        },
        'f' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.False;
        },
        'n' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.Null;
        },
        '-', '0'...'9' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.Number;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidValue;
        },
    }
}

pub fn handleArrayComma(parser: *types.MinifyingParser, byte: u8) !void {
    if (utils.isWhitespace(byte)) return;

    switch (byte) {
        ',' => {
            try pretty.writeByte(parser, byte);
            try pretty.writeNewline(parser);
            parser.state = types.State.ArrayValue;
        },
        ']' => {
            pretty.decreaseIndent(parser);
            try pretty.writeNewline(parser);
            try pretty.writeIndentIfNeeded(parser);
            try pretty.writeByte(parser, byte);
            _ = parser.popContext();
            const context = parser.getCurrentContext();
            switch (context) {
                .Object => parser.state = types.State.ObjectComma,
                .Array => parser.state = types.State.ArrayComma,
                .TopLevel => parser.state = types.State.TopLevel,
            }
        },
        else => {
            parser.state = types.State.Error;
            return error.UnexpectedCharacter;
        },
    }
}

pub fn handleString(parser: *types.MinifyingParser, byte: u8) !void {
    switch (byte) {
        '"' => {
            try pretty.writeByte(parser, byte);
            const context = parser.getCurrentContext();
            switch (context) {
                .Object => parser.state = types.State.ObjectComma,
                .Array => parser.state = types.State.ArrayComma,
                .TopLevel => parser.state = types.State.TopLevel,
            }
        },
        '\\' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.StringEscape;
        },
        else => try pretty.writeByte(parser, byte),
    }
}

pub fn handleStringEscape(parser: *types.MinifyingParser, byte: u8) !void {
    switch (byte) {
        '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.String;
        },
        'u' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.StringEscapeUnicode;
            parser.string_unicode_bytes_remaining = 4;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidEscapeSequence;
        },
    }
}

pub fn handleStringEscapeUnicode(parser: *types.MinifyingParser, byte: u8) !void {
    if (utils.isHexDigit(byte)) {
        try pretty.writeByte(parser, byte);
        parser.string_unicode_bytes_remaining -= 1;
        if (parser.string_unicode_bytes_remaining == 0) {
            parser.state = types.State.String;
        }
    } else {
        parser.state = types.State.Error;
        return error.InvalidUnicodeEscape;
    }
}

pub fn handleNumber(parser: *types.MinifyingParser, byte: u8) !void {
    switch (byte) {
        '0'...'9' => try pretty.writeByte(parser, byte),
        '.' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.NumberDecimal;
        },
        'e', 'E' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.NumberExponent;
        },
        else => {
            const context = parser.getCurrentContext();
            switch (context) {
                .Object => {
                    parser.state = types.State.ObjectComma;
                    try handleObjectComma(parser, byte);
                },
                .Array => {
                    parser.state = types.State.ArrayComma;
                    try handleArrayComma(parser, byte);
                },
                .TopLevel => parser.state = types.State.TopLevel,
            }
        },
    }
}

pub fn handleNumberDecimal(parser: *types.MinifyingParser, byte: u8) !void {
    switch (byte) {
        '0'...'9' => try pretty.writeByte(parser, byte),
        'e', 'E' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.NumberExponent;
        },
        else => {
            const context = parser.getCurrentContext();
            switch (context) {
                .Object => {
                    parser.state = types.State.ObjectComma;
                    try handleObjectComma(parser, byte);
                },
                .Array => {
                    parser.state = types.State.ArrayComma;
                    try handleArrayComma(parser, byte);
                },
                .TopLevel => parser.state = types.State.TopLevel,
            }
        },
    }
}

pub fn handleNumberExponent(parser: *types.MinifyingParser, byte: u8) !void {
    switch (byte) {
        '+', '-' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.NumberExponentSign;
        },
        '0'...'9' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.NumberExponentSign;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidNumber;
        },
    }
}

pub fn handleNumberExponentSign(parser: *types.MinifyingParser, byte: u8) !void {
    switch (byte) {
        '0'...'9' => try pretty.writeByte(parser, byte),
        else => {
            const context = parser.getCurrentContext();
            switch (context) {
                .Object => {
                    parser.state = types.State.ObjectComma;
                    try handleObjectComma(parser, byte);
                },
                .Array => {
                    parser.state = types.State.ArrayComma;
                    try handleArrayComma(parser, byte);
                },
                .TopLevel => parser.state = types.State.TopLevel,
            }
        },
    }
}

pub fn handleTrue(parser: *types.MinifyingParser, byte: u8) !void {
    const expected = [_]u8{ 'r', 'u', 'e' };
    if (parser.count < expected.len) {
        if (byte == expected[parser.count]) {
            try pretty.writeByte(parser, byte);
            parser.count += 1;
        } else {
            parser.state = types.State.Error;
            return error.InvalidTrue;
        }
    } else {
        parser.count = 0;
        const context = parser.getCurrentContext();
        switch (context) {
            .Object => {
                parser.state = types.State.ObjectComma;
                try handleObjectComma(parser, byte);
            },
            .Array => {
                parser.state = types.State.ArrayComma;
                try handleArrayComma(parser, byte);
            },
            .TopLevel => parser.state = types.State.TopLevel,
        }
    }
}

pub fn handleFalse(parser: *types.MinifyingParser, byte: u8) !void {
    const expected = [_]u8{ 'a', 'l', 's', 'e' };
    if (parser.count < expected.len) {
        if (byte == expected[parser.count]) {
            try pretty.writeByte(parser, byte);
            parser.count += 1;
        } else {
            parser.state = types.State.Error;
            return error.InvalidFalse;
        }
    } else {
        parser.count = 0;
        const context = parser.getCurrentContext();
        switch (context) {
            .Object => {
                parser.state = types.State.ObjectComma;
                try handleObjectComma(parser, byte);
            },
            .Array => {
                parser.state = types.State.ArrayComma;
                try handleArrayComma(parser, byte);
            },
            .TopLevel => parser.state = types.State.TopLevel,
        }
    }
}

pub fn handleNull(parser: *types.MinifyingParser, byte: u8) !void {
    const expected = [_]u8{ 'u', 'l', 'l' };
    if (parser.count < expected.len) {
        if (byte == expected[parser.count]) {
            try pretty.writeByte(parser, byte);
            parser.count += 1;
        } else {
            parser.state = types.State.Error;
            return error.InvalidNull;
        }
    } else {
        parser.count = 0;
        const context = parser.getCurrentContext();
        switch (context) {
            .Object => {
                parser.state = types.State.ObjectComma;
                try handleObjectComma(parser, byte);
            },
            .Array => {
                parser.state = types.State.ArrayComma;
                try handleArrayComma(parser, byte);
            },
            .TopLevel => parser.state = types.State.TopLevel,
        }
    }
}
