const std = @import("std");
const types = @import("types.zig");
const utils = @import("utils.zig");
const pretty = @import("pretty.zig");
const simd_utils = @import("simd_utils.zig");

const SimdUtils = simd_utils.SimdUtils;

/// Optimized top-level handler using SIMD whitespace skipping
pub fn handleTopLevelOptimized(parser: *types.MinifyingParser, input: []const u8, pos: *usize) !void {
    // Skip whitespace using SIMD
    const start = SimdUtils.skipWhitespaceSimd64(input, pos.*);
    pos.* = start;

    if (start >= input.len) return;

    const byte = input[start];
    pos.* += 1;

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
        '"' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.String;
        },
        '0'...'9', '-' => {
            try pretty.writeByte(parser, byte);
            parser.state = types.State.Number;
        },
        't' => {
            try pretty.writeByte(parser, byte);
            parser.count = 0;
            parser.state = types.State.True;
        },
        'f' => {
            try pretty.writeByte(parser, byte);
            parser.count = 0;
            parser.state = types.State.False;
        },
        'n' => {
            try pretty.writeByte(parser, byte);
            parser.count = 0;
            parser.state = types.State.Null;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidTopLevel;
        },
    }
}

/// Optimized string handler using SIMD copy and escape detection
pub fn handleStringOptimized(parser: *types.MinifyingParser, input: []const u8, pos: *usize) !usize {
    const start_pos = pos.*;
    var string_start = start_pos;

    // Look for string end using SIMD
    while (pos.* + SimdUtils.vector_size <= input.len) {
        const classification = SimdUtils.classifyCharsSimd(input, pos.*);

        if (classification.quote_mask != 0 or classification.backslash_mask != 0) {
            // Found quote or backslash, need detailed processing
            var i: usize = 0;
            while (i < SimdUtils.vector_size and pos.* + i < input.len) : (i += 1) {
                const c = input[pos.* + i];

                if (c == '"') {
                    // Copy the string content
                    const string_content = input[string_start .. pos.* + i];
                    try pretty.writeBytes(parser, string_content);
                    try pretty.writeByte(parser, '"');
                    pos.* = pos.* + i + 1;

                    // Determine next state
                    const context = parser.getCurrentContext();
                    switch (context) {
                        .Object => {
                            if (parser.state == types.State.ObjectKey or
                                parser.state == types.State.ObjectKeyString)
                            {
                                parser.state = types.State.ObjectColon;
                            } else {
                                parser.state = types.State.ObjectComma;
                            }
                        },
                        .Array => parser.state = types.State.ArrayComma,
                        .TopLevel => parser.state = types.State.TopLevel,
                    }

                    return pos.* - start_pos;
                } else if (c == '\\') {
                    // Copy up to escape
                    if (pos.* + i > string_start) {
                        const chunk = input[string_start .. pos.* + i];
                        try pretty.writeBytes(parser, chunk);
                    }

                    // Handle escape sequence
                    pos.* = pos.* + i;
                    parser.state = types.State.StringEscape;
                    return pos.* - start_pos;
                }
            }

            // No string end in this chunk, copy and continue
            const chunk = input[string_start .. pos.* + SimdUtils.vector_size];
            try pretty.writeBytes(parser, chunk);
            string_start = pos.* + SimdUtils.vector_size;
        }

        pos.* += SimdUtils.vector_size;
    }

    // Handle remaining bytes
    while (pos.* < input.len) : (pos.* += 1) {
        const c = input[pos.*];
        if (c == '"') {
            // Copy final chunk
            if (pos.* > string_start) {
                const chunk = input[string_start..pos.*];
                try pretty.writeBytes(parser, chunk);
            }
            try pretty.writeByte(parser, '"');
            pos.* += 1;

            // Set next state
            const context = parser.getCurrentContext();
            switch (context) {
                .Object => {
                    if (parser.state == types.State.ObjectKey or
                        parser.state == types.State.ObjectKeyString)
                    {
                        parser.state = types.State.ObjectColon;
                    } else {
                        parser.state = types.State.ObjectComma;
                    }
                },
                .Array => parser.state = types.State.ArrayComma,
                .TopLevel => parser.state = types.State.TopLevel,
            }

            return pos.* - start_pos;
        } else if (c == '\\') {
            // Copy up to escape
            if (pos.* > string_start) {
                const chunk = input[string_start..pos.*];
                try pretty.writeBytes(parser, chunk);
            }
            parser.state = types.State.StringEscape;
            return pos.* - start_pos;
        }
    }

    // Copy remaining
    if (pos.* > string_start) {
        const chunk = input[string_start..pos.*];
        try pretty.writeBytes(parser, chunk);
    }

    return pos.* - start_pos;
}

/// Optimized number handler using SIMD
pub fn handleNumberOptimized(parser: *types.MinifyingParser, input: []const u8, pos: *usize) !usize {
    const start_pos = pos.*;

    // Use SIMD to find end of number
    const end_pos = SimdUtils.findNumberEndSimd(input, start_pos);

    // Copy entire number
    const number_str = input[start_pos..end_pos];
    try pretty.writeBytes(parser, number_str);

    pos.* = end_pos;

    // Determine next state
    const context = parser.getCurrentContext();
    switch (context) {
        .Object => parser.state = types.State.ObjectComma,
        .Array => parser.state = types.State.ArrayComma,
        .TopLevel => parser.state = types.State.TopLevel,
    }

    return end_pos - start_pos;
}

/// Optimized object value handler
pub fn handleObjectValueOptimized(parser: *types.MinifyingParser, input: []const u8, pos: *usize) !void {
    // Skip whitespace using SIMD
    const start = SimdUtils.skipWhitespaceSimd64(input, pos.*);
    pos.* = start;

    if (start >= input.len) return;

    const byte = input[start];

    switch (byte) {
        '"' => {
            try pretty.writeByte(parser, byte);
            pos.* += 1;
            parser.state = types.State.String;
        },
        '{' => {
            try pretty.writeByte(parser, byte);
            try parser.pushContext(types.Context.Object);
            pretty.increaseIndent(parser);
            try pretty.writeNewline(parser);
            pos.* += 1;
            parser.state = types.State.ObjectStart;
        },
        '[' => {
            try pretty.writeByte(parser, byte);
            try parser.pushContext(types.Context.Array);
            pretty.increaseIndent(parser);
            try pretty.writeNewline(parser);
            pos.* += 1;
            parser.state = types.State.ArrayStart;
        },
        '0'...'9', '-' => {
            parser.state = types.State.Number;
        },
        't' => {
            try pretty.writeByte(parser, byte);
            parser.count = 0;
            pos.* += 1;
            parser.state = types.State.True;
        },
        'f' => {
            try pretty.writeByte(parser, byte);
            parser.count = 0;
            pos.* += 1;
            parser.state = types.State.False;
        },
        'n' => {
            try pretty.writeByte(parser, byte);
            parser.count = 0;
            pos.* += 1;
            parser.state = types.State.Null;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidObjectValue;
        },
    }
}

/// Optimized array value handler
pub fn handleArrayValueOptimized(parser: *types.MinifyingParser, input: []const u8, pos: *usize) !void {
    // Skip whitespace using SIMD
    const start = SimdUtils.skipWhitespaceSimd64(input, pos.*);
    pos.* = start;

    if (start >= input.len) return;

    const byte = input[start];

    switch (byte) {
        ']' => {
            // Empty array or trailing comma
            pretty.decreaseIndent(parser);
            try pretty.writeNewline(parser);
            try pretty.writeIndentIfNeeded(parser);
            try pretty.writeByte(parser, byte);
            _ = parser.popContext();
            pos.* += 1;

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
            pos.* += 1;
            parser.state = types.State.String;
        },
        '{' => {
            try pretty.writeIndentIfNeeded(parser);
            try pretty.writeByte(parser, byte);
            try parser.pushContext(types.Context.Object);
            pretty.increaseIndent(parser);
            try pretty.writeNewline(parser);
            pos.* += 1;
            parser.state = types.State.ObjectStart;
        },
        '[' => {
            try pretty.writeIndentIfNeeded(parser);
            try pretty.writeByte(parser, byte);
            try parser.pushContext(types.Context.Array);
            pretty.increaseIndent(parser);
            try pretty.writeNewline(parser);
            pos.* += 1;
            parser.state = types.State.ArrayStart;
        },
        '0'...'9', '-' => {
            try pretty.writeIndentIfNeeded(parser);
            parser.state = types.State.Number;
        },
        't' => {
            try pretty.writeIndentIfNeeded(parser);
            try pretty.writeByte(parser, byte);
            parser.count = 0;
            pos.* += 1;
            parser.state = types.State.True;
        },
        'f' => {
            try pretty.writeIndentIfNeeded(parser);
            try pretty.writeByte(parser, byte);
            parser.count = 0;
            pos.* += 1;
            parser.state = types.State.False;
        },
        'n' => {
            try pretty.writeIndentIfNeeded(parser);
            try pretty.writeByte(parser, byte);
            parser.count = 0;
            pos.* += 1;
            parser.state = types.State.Null;
        },
        else => {
            parser.state = types.State.Error;
            return error.InvalidArrayValue;
        },
    }
}

/// Process entire string using SIMD (for when we have full string in buffer)
pub fn processStringSimd(input: []const u8, output: []u8) !usize {
    const result = SimdUtils.copyStringSimd(input, output, 0, input.len);
    return result.bytes_copied;
}

/// Process number using SIMD to find boundaries
pub fn processNumberSimd(input: []const u8, start: usize) usize {
    return SimdUtils.findNumberEndSimd(input, start);
}
