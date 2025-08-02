const std = @import("std");
const Allocator = std.mem.Allocator;

/// Configuration for the streaming parser
pub const ParserConfig = struct {
    /// Chunk size for reading input data
    chunk_size: usize = 256 * 1024, // 256KB default

    /// Enable SIMD optimizations
    enable_simd: bool = true,

    /// SIMD instruction set to use
    simd_level: SimdLevel = .auto,

    /// Memory pool size for temporary allocations
    memory_pool_size: usize = 1024 * 1024, // 1MB default

    /// Enable zero-copy token streams
    zero_copy_tokens: bool = true,

    /// Maximum token buffer size
    max_token_buffer: usize = 1024 * 1024, // 1MB default
};

/// SIMD instruction set levels
pub const SimdLevel = enum {
    none,
    sse2,
    avx2,
    avx512,
    neon,
    auto,
};

/// JSON token types
pub const TokenType = enum {
    // Structural tokens
    object_start, // {
    object_end, // }
    array_start, // [
    array_end, // ]
    comma, // ,
    colon, // :

    // Value tokens
    string,
    number,
    boolean_true,
    boolean_false,
    null,

    // Special tokens
    whitespace,
    comment,
    eof,
    parse_error,
};

/// A zero-copy token representing a JSON element
pub const Token = struct {
    /// Token type
    token_type: TokenType,

    /// Start position in the input stream
    start: usize,

    /// End position in the input stream (exclusive)
    end: usize,

    /// Line number for error reporting
    line: usize,

    /// Column number for error reporting
    column: usize,

    /// Token value (for strings, numbers, etc.)
    value: ?[]const u8 = null,

    /// Error message if token_type is .parse_error
    error_message: ?[]const u8 = null,

    pub fn init(token_type: TokenType, start: usize, end: usize, line: usize, column: usize) Token {
        return Token{
            .token_type = token_type,
            .start = start,
            .end = end,
            .line = line,
            .column = column,
            .value = null,
            .error_message = null,
        };
    }

    pub fn withValue(self: Token, value: []const u8) Token {
        var token = self;
        token.value = value;
        return token;
    }

    pub fn withError(self: Token, message: []const u8) Token {
        var token = self;
        token.token_type = .parse_error;
        token.error_message = message;
        return token;
    }
};

/// Zero-copy token stream for efficient token access
pub const TokenStream = struct {
    const Self = @This();

    /// Tokens in the stream
    tokens: std.ArrayList(Token),

    /// Current position in the stream
    position: usize = 0,

    /// Input data reference for zero-copy access
    input_data: []const u8,

    pub fn init(allocator: Allocator, input_data: []const u8) Self {
        return Self{
            .tokens = std.ArrayList(Token).init(allocator),
            .input_data = input_data,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    pub fn addToken(self: *Self, token: Token) !void {
        try self.tokens.append(token);
    }

    pub fn getToken(self: *const Self, index: usize) ?Token {
        if (index >= self.tokens.items.len) return null;
        return self.tokens.items[index];
    }

    pub fn getCurrentToken(self: *Self) ?Token {
        return self.getToken(self.position);
    }

    pub fn advance(self: *Self) void {
        if (self.position < self.tokens.items.len) {
            self.position += 1;
        }
    }

    pub fn reset(self: *Self) void {
        self.position = 0;
    }

    pub fn hasMore(self: *Self) bool {
        return self.position < self.tokens.items.len;
    }

    pub fn getTokenValue(self: *Self, token: Token) ?[]const u8 {
        if (token.value) |value| return value;
        if (token.start < token.end and token.end <= self.input_data.len) {
            return self.input_data[token.start..token.end];
        }
        return null;
    }

    pub fn getTokenCount(self: *const Self) usize {
        return self.tokens.items.len;
    }

    pub fn getPosition(self: *Self) usize {
        return self.position;
    }
};

/// SIMD-optimized parser for high-performance JSON parsing
pub const SimdParser = struct {
    const Self = @This();

    /// SIMD level being used
    simd_level: SimdLevel,

    pub fn init(target: std.Target) Self {
        const simd_level = detectSimdLevel(target);
        return Self{
            .simd_level = simd_level,
        };
    }

    fn detectSimdLevel(target: std.Target) SimdLevel {
        if (target.cpu.arch != .x86_64) {
            if (target.cpu.arch == .aarch64) return .neon;
            return .none;
        }

        if (target.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.avx512f))) {
            return .avx512;
        } else if (target.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.avx2))) {
            return .avx2;
        } else if (target.cpu.features.isEnabled(@intFromEnum(std.Target.x86.Feature.sse2))) {
            return .sse2;
        }

        return .none;
    }

    pub fn parseChunk(self: *Self, data: []const u8, callback: ParseCallback) !void {
        switch (self.simd_level) {
            .avx512 => try self.parseChunkAvx512(data, callback),
            .avx2 => try self.parseChunkAvx2(data, callback),
            .sse2 => try self.parseChunkSse2(data, callback),
            .neon => try self.parseChunkNeon(data, callback),
            .none => try self.parseChunkScalar(data, callback),
            .auto => unreachable, // Should be resolved during init
        }
    }

    fn parseChunkAvx512(self: *Self, data: []const u8, callback: ParseCallback) !void {
        // AVX-512 optimized parsing for structural JSON tokens
        const Vector = @Vector(64, u8); // AVX-512 processes 64 bytes at once
        
        var pos: usize = 0;
        const chunk_size = 64;
        
        // Process data in 64-byte chunks using AVX-512
        while (pos + chunk_size <= data.len) {
            const chunk: Vector = data[pos..pos + chunk_size][0..chunk_size].*;
            
            // Define structural character vectors for comparison
            const lbrace: Vector = @splat('{');
            const rbrace: Vector = @splat('}');
            const lbracket: Vector = @splat('[');
            const rbracket: Vector = @splat(']');
            const comma: Vector = @splat(',');
            const colon: Vector = @splat(':');
            const quote: Vector = @splat('"');
            const space: Vector = @splat(' ');
            const tab: Vector = @splat('\t');
            const newline: Vector = @splat('\n');
            const carriage: Vector = @splat('\r');
            
            // Find structural characters using SIMD comparison
            const is_lbrace = chunk == lbrace;
            const is_rbrace = chunk == rbrace;
            const is_lbracket = chunk == lbracket;
            const is_rbracket = chunk == rbracket;
            const is_comma = chunk == comma;
            const is_colon = chunk == colon;
            const is_quote = chunk == quote;
            
            // Find whitespace characters (for future whitespace handling)
            const is_space = chunk == space;
            const is_tab = chunk == tab;
            const is_newline = chunk == newline;
            const is_carriage = chunk == carriage;
            _ = is_space;
            _ = is_tab;
            _ = is_newline; 
            _ = is_carriage;
            
            // Combine all structural characters using vector operations
            const BoolVector = @Vector(64, bool);
            const is_structural = @select(bool, is_lbrace, @as(BoolVector, @splat(true)), 
                                 @select(bool, is_rbrace, @as(BoolVector, @splat(true)),
                                 @select(bool, is_lbracket, @as(BoolVector, @splat(true)),
                                 @select(bool, is_rbracket, @as(BoolVector, @splat(true)), 
                                 @select(bool, is_comma, @as(BoolVector, @splat(true)),
                                 @select(bool, is_colon, @as(BoolVector, @splat(true)),
                                 @select(bool, is_quote, @as(BoolVector, @splat(true)), @as(BoolVector, @splat(false)))))))));
            
            // Process each byte in the chunk where structural characters were found
            var i: usize = 0;
            while (i < chunk_size) {
                // Check if this position has a structural character
                const struct_mask = is_structural[i];
                if (struct_mask) {
                    const char = data[pos + i];
                    switch (char) {
                        '{' => {
                            try callback(Token.init(.object_start, pos + i, pos + i + 1, 1, pos + i + 1));
                            i += 1;
                        },
                        '}' => {
                            try callback(Token.init(.object_end, pos + i, pos + i + 1, 1, pos + i + 1));
                            i += 1;
                        },
                        '[' => {
                            try callback(Token.init(.array_start, pos + i, pos + i + 1, 1, pos + i + 1));
                            i += 1;
                        },
                        ']' => {
                            try callback(Token.init(.array_end, pos + i, pos + i + 1, 1, pos + i + 1));
                            i += 1;
                        },
                        ',' => {
                            try callback(Token.init(.comma, pos + i, pos + i + 1, 1, pos + i + 1));
                            i += 1;
                        },
                        ':' => {
                            try callback(Token.init(.colon, pos + i, pos + i + 1, 1, pos + i + 1));
                            i += 1;
                        },
                        '"' => {
                            // Use vectorized string parsing
                            if (pos + i + 1 < data.len) {
                                const string_result = try self.parseStringAvx512(data, pos + i, callback);
                                i = string_result.next_pos - pos;
                            } else {
                                try callback(Token.init(.parse_error, pos + i, pos + i + 1, 1, pos + i + 1).withError("Unterminated string"));
                                i += 1;
                            }
                        },
                        '0'...'9', '-' => {
                            // Use vectorized number parsing
                            const number_result = try self.parseNumberAvx512(data, pos + i, callback);
                            i = number_result.next_pos - pos;
                        },
                        else => {
                            try callback(Token.init(.parse_error, pos + i, pos + i + 1, 1, pos + i + 1).withError("Invalid character"));
                            i += 1;
                        },
                    }
                } else {
                    i += 1;
                }
            }
            
            pos += chunk_size;
        }
        
        // Process remaining bytes with scalar parsing
        if (pos < data.len) {
            try self.parseChunkScalar(data[pos..], callback);
        }
    }

    fn parseChunkAvx2(self: *Self, data: []const u8, callback: ParseCallback) !void {
        // TODO: Implement AVX2 optimized parsing
        try self.parseChunkScalar(data, callback);
    }

    fn parseChunkSse2(self: *Self, data: []const u8, callback: ParseCallback) !void {
        // TODO: Implement SSE2 optimized parsing
        try self.parseChunkScalar(data, callback);
    }

    fn parseChunkNeon(self: *Self, data: []const u8, callback: ParseCallback) !void {
        // TODO: Implement NEON optimized parsing
        try self.parseChunkScalar(data, callback);
    }

    /// Result of vectorized string parsing
    const StringParseResult = struct {
        next_pos: usize,
        has_escapes: bool,
    };

    /// Result of vectorized number parsing
    const NumberParseResult = struct {
        next_pos: usize,
        is_valid: bool,
    };

    /// AVX-512 optimized string parsing
    fn parseStringAvx512(_: *Self, data: []const u8, start_pos: usize, callback: ParseCallback) !StringParseResult {
        const Vector = @Vector(64, u8);
        
        if (start_pos >= data.len or data[start_pos] != '"') {
            return StringParseResult{ .next_pos = start_pos + 1, .has_escapes = false };
        }
        
        var pos = start_pos + 1; // Skip opening quote
        var has_escapes = false;
        const start_line: usize = 1; // TODO: Track line numbers properly
        const start_column = start_pos + 1;
        
        // Process string content in 64-byte chunks using AVX-512
        while (pos + 64 <= data.len) {
            const chunk: Vector = data[pos..pos + 64][0..64].*;
            
            // Define search vectors
            const quote_vec: Vector = @splat('"');
            const backslash_vec: Vector = @splat('\\');
            const newline_vec: Vector = @splat('\n');
            const control_threshold: Vector = @splat(32); // Control characters < 32
            
            // Find special characters
            const is_quote = chunk == quote_vec;
            const is_backslash = chunk == backslash_vec;
            const is_newline = chunk == newline_vec;
            const is_control = chunk < control_threshold;
            
            // Combine all terminating conditions
            const BoolVector = @Vector(64, bool);
            const is_terminator = @select(bool, is_quote, @as(BoolVector, @splat(true)),
                                 @select(bool, is_backslash, @as(BoolVector, @splat(true)),
                                 @select(bool, is_newline, @as(BoolVector, @splat(true)),
                                 @select(bool, is_control, @as(BoolVector, @splat(true)), @as(BoolVector, @splat(false))))));
            
            // Check if any terminator was found in this chunk
            var found_terminator = false;
            var terminator_pos: usize = 0;
            
            for (0..64) |i| {
                if (is_terminator[i]) {
                    found_terminator = true;
                    terminator_pos = i;
                    break;
                }
            }
            
            if (found_terminator) {
                const abs_pos = pos + terminator_pos;
                const char = data[abs_pos];
                
                if (char == '"') {
                    // Found closing quote - emit string token
                    try callback(Token.init(.string, start_pos, abs_pos + 1, start_line, start_column));
                    return StringParseResult{ .next_pos = abs_pos + 1, .has_escapes = has_escapes };
                } else if (char == '\\') {
                    // Found escape sequence - set flag and skip escaped char
                    has_escapes = true;
                    pos = abs_pos + 2; // Skip backslash and next character
                    if (pos > data.len) {
                        try callback(Token.init(.parse_error, start_pos, pos, start_line, start_column).withError("Unterminated string escape"));
                        return StringParseResult{ .next_pos = pos, .has_escapes = has_escapes };
                    }
                } else if (char == '\n' or char < 32) {
                    // Invalid character in string
                    try callback(Token.init(.parse_error, start_pos, abs_pos, start_line, start_column).withError("Invalid character in string"));
                    return StringParseResult{ .next_pos = abs_pos + 1, .has_escapes = has_escapes };
                }
            } else {
                // No terminators found in this chunk, continue to next chunk
                pos += 64;
            }
        }
        
        // Handle remaining bytes with scalar parsing
        while (pos < data.len) {
            const char = data[pos];
            if (char == '"') {
                try callback(Token.init(.string, start_pos, pos + 1, start_line, start_column));
                return StringParseResult{ .next_pos = pos + 1, .has_escapes = has_escapes };
            } else if (char == '\\') {
                has_escapes = true;
                pos += 2; // Skip escape sequence
                if (pos > data.len) break;
            } else if (char == '\n' or char < 32) {
                try callback(Token.init(.parse_error, start_pos, pos, start_line, start_column).withError("Invalid character in string"));
                return StringParseResult{ .next_pos = pos + 1, .has_escapes = has_escapes };
            } else {
                pos += 1;
            }
        }
        
        // Unterminated string
        try callback(Token.init(.parse_error, start_pos, pos, start_line, start_column).withError("Unterminated string"));
        return StringParseResult{ .next_pos = pos, .has_escapes = has_escapes };
    }

    /// AVX-512 optimized number parsing
    fn parseNumberAvx512(_: *Self, data: []const u8, start_pos: usize, callback: ParseCallback) !NumberParseResult {
        const Vector = @Vector(64, u8);
        
        if (start_pos >= data.len) {
            return NumberParseResult{ .next_pos = start_pos + 1, .is_valid = false };
        }
        
        var pos = start_pos;
        const start_line: usize = 1; // TODO: Track line numbers properly
        const start_column = start_pos + 1;
        
        // Handle initial minus sign
        if (data[pos] == '-') {
            pos += 1;
            if (pos >= data.len) {
                try callback(Token.init(.parse_error, start_pos, pos, start_line, start_column).withError("Invalid number: lone minus"));
                return NumberParseResult{ .next_pos = pos, .is_valid = false };
            }
        }
        
        // Use SIMD to quickly scan for valid number characters
        while (pos + 64 <= data.len) {
            const chunk: Vector = data[pos..pos + 64][0..64].*;
            
            // Define number character vectors
            const zero_vec: Vector = @splat('0');
            const nine_vec: Vector = @splat('9');
            const dot_vec: Vector = @splat('.');
            const e_lower_vec: Vector = @splat('e');
            const e_upper_vec: Vector = @splat('E');
            const plus_vec: Vector = @splat('+');
            const minus_vec: Vector = @splat('-');
            const space_vec: Vector = @splat(' ');
            const tab_vec: Vector = @splat('\t');
            const newline_vec: Vector = @splat('\n');
            const comma_vec: Vector = @splat(',');
            const rbrace_vec: Vector = @splat('}');
            const rbracket_vec: Vector = @splat(']');
            
            const BoolVector = @Vector(64, bool);
            
            // Check for digit characters (0-9)
            const is_digit_ge = chunk >= zero_vec;
            const is_digit_le = chunk <= nine_vec;
            const is_digit = @select(bool, is_digit_ge, @select(bool, is_digit_le, @as(BoolVector, @splat(true)), @as(BoolVector, @splat(false))), @as(BoolVector, @splat(false)));
            
            // Check for valid number characters
            const is_dot = chunk == dot_vec;
            const is_e_lower = chunk == e_lower_vec;
            const is_e_upper = chunk == e_upper_vec;
            const is_plus = chunk == plus_vec;
            const is_minus = chunk == minus_vec;
            
            // Check for number terminators (whitespace, structural chars)
            const is_space = chunk == space_vec;
            const is_tab = chunk == tab_vec;
            const is_newline = chunk == newline_vec;
            const is_comma = chunk == comma_vec;
            const is_rbrace = chunk == rbrace_vec;
            const is_rbracket = chunk == rbracket_vec;
            
            // Combine all valid number characters
            const is_number_char = @select(bool, is_digit, @as(BoolVector, @splat(true)),
                                  @select(bool, is_dot, @as(BoolVector, @splat(true)),
                                  @select(bool, is_e_lower, @as(BoolVector, @splat(true)),
                                  @select(bool, is_e_upper, @as(BoolVector, @splat(true)),
                                  @select(bool, is_plus, @as(BoolVector, @splat(true)),
                                  @select(bool, is_minus, @as(BoolVector, @splat(true)), @as(BoolVector, @splat(false))))))));
            
            // Combine all terminator characters
            const is_terminator = @select(bool, is_space, @as(BoolVector, @splat(true)),
                                 @select(bool, is_tab, @as(BoolVector, @splat(true)),
                                 @select(bool, is_newline, @as(BoolVector, @splat(true)),
                                 @select(bool, is_comma, @as(BoolVector, @splat(true)),
                                 @select(bool, is_rbrace, @as(BoolVector, @splat(true)),
                                 @select(bool, is_rbracket, @as(BoolVector, @splat(true)), @as(BoolVector, @splat(false))))))));
            
            // Find first non-number character or terminator
            var found_end = false;
            var end_pos: usize = 0;
            
            for (0..64) |i| {
                if (!is_number_char[i] or is_terminator[i]) {
                    found_end = true;
                    end_pos = i;
                    break;
                }
            }
            
            if (found_end) {
                const final_pos = pos + end_pos;
                // Emit number token
                try callback(Token.init(.number, start_pos, final_pos, start_line, start_column));
                return NumberParseResult{ .next_pos = final_pos, .is_valid = true };
            } else {
                // Continue to next chunk - all characters were valid number chars
                pos += 64;
            }
        }
        
        // Handle remaining bytes with scalar parsing
        while (pos < data.len) {
            const char = data[pos];
            if ((char >= '0' and char <= '9') or char == '.' or char == 'e' or char == 'E' or char == '+' or char == '-') {
                pos += 1;
            } else {
                break;
            }
        }
        
        // Emit number token
        try callback(Token.init(.number, start_pos, pos, start_line, start_column));
        return NumberParseResult{ .next_pos = pos, .is_valid = true };
    }

    fn parseChunkScalar(_: *Self, data: []const u8, callback: ParseCallback) !void {
        var i: usize = 0;
        var line: usize = 1;
        var column: usize = 1;

        while (i < data.len) : (i += 1) {
            const byte = data[i];

            switch (byte) {
                '{' => {
                    try callback(Token.init(.object_start, i, i + 1, line, column));
                    column += 1;
                },
                '}' => {
                    try callback(Token.init(.object_end, i, i + 1, line, column));
                    column += 1;
                },
                '[' => {
                    try callback(Token.init(.array_start, i, i + 1, line, column));
                    column += 1;
                },
                ']' => {
                    try callback(Token.init(.array_end, i, i + 1, line, column));
                    column += 1;
                },
                ',' => {
                    try callback(Token.init(.comma, i, i + 1, line, column));
                    column += 1;
                },
                ':' => {
                    try callback(Token.init(.colon, i, i + 1, line, column));
                    column += 1;
                },
                '"' => {
                    const start = i;
                    const start_line = line;
                    const start_column = column;

                    // Parse string
                    i += 1;
                    column += 1;
                    while (i < data.len) : (i += 1) {
                        const ch = data[i];
                        if (ch == '"') {
                            break;
                        } else if (ch == '\\') {
                            i += 1; // Skip escaped character
                            if (i >= data.len) {
                                try callback(Token.init(.parse_error, start, i, start_line, start_column).withError("Unterminated string"));
                                return;
                            }
                        } else if (ch == '\n') {
                            line += 1;
                            column = 1;
                        } else {
                            column += 1;
                        }
                    }

                    if (i >= data.len) {
                        try callback(Token.init(.parse_error, start, i, start_line, start_column).withError("Unterminated string"));
                        return;
                    }

                    try callback(Token.init(.string, start, i + 1, start_line, start_column));
                    column += 1;
                },
                ' ', '\t', '\r' => {
                    column += 1;
                },
                '\n' => {
                    line += 1;
                    column = 1;
                },
                '0'...'9', '-' => {
                    const start = i;
                    const start_line = line;
                    const start_column = column;

                    // Parse number
                    while (i < data.len) : (i += 1) {
                        const ch = data[i];
                        if ((ch >= '0' and ch <= '9') or ch == '.' or ch == 'e' or ch == 'E' or ch == '+' or ch == '-') {
                            column += 1;
                        } else {
                            break;
                        }
                    }

                    try callback(Token.init(.number, start, i, start_line, start_column));
                    i -= 1; // Adjust for loop increment
                },
                't' => {
                    if (i + 3 < data.len and std.mem.eql(u8, data[i .. i + 4], "true")) {
                        try callback(Token.init(.boolean_true, i, i + 4, line, column));
                        i += 3;
                        column += 4;
                    } else {
                        try callback(Token.init(.parse_error, i, i + 1, line, column).withError("Invalid token"));
                    }
                },
                'f' => {
                    if (i + 4 < data.len and std.mem.eql(u8, data[i .. i + 5], "false")) {
                        try callback(Token.init(.boolean_false, i, i + 5, line, column));
                        i += 4;
                        column += 5;
                    } else {
                        try callback(Token.init(.parse_error, i, i + 1, line, column).withError("Invalid token"));
                    }
                },
                'n' => {
                    if (i + 3 < data.len and std.mem.eql(u8, data[i .. i + 4], "null")) {
                        try callback(Token.init(.null, i, i + 4, line, column));
                        i += 3;
                        column += 4;
                    } else {
                        try callback(Token.init(.parse_error, i, i + 1, line, column).withError("Invalid token"));
                    }
                },
                else => {
                    try callback(Token.init(.parse_error, i, i + 1, line, column).withError("Unexpected character"));
                },
            }
        }
    }
};

/// Memory pool for efficient allocation of temporary structures
pub const MemoryPool = struct {
    const Self = @This();

    /// Pool size
    size: usize,

    /// Allocator
    allocator: Allocator,

    /// Memory blocks
    blocks: std.ArrayList([]u8),

    /// Current block index
    current_block: usize = 0,

    /// Current position in current block
    current_pos: usize = 0,

    pub fn init(allocator: Allocator, size: usize) Self {
        return Self{
            .size = size,
            .allocator = allocator,
            .blocks = std.ArrayList([]u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.blocks.items) |block| {
            self.allocator.free(block);
        }
        self.blocks.deinit();
    }

    pub fn allocate(self: *Self, size: usize) ![]u8 {
        if (size > self.size) {
            // Large allocation, allocate directly
            return self.allocator.alloc(u8, size);
        }

        // Check if current block has enough space
        if (self.current_block < self.blocks.items.len) {
            const current_block = self.blocks.items[self.current_block];
            if (self.current_pos + size <= current_block.len) {
                const result = current_block[self.current_pos .. self.current_pos + size];
                self.current_pos += size;
                return result;
            }
        }

        // Need new block
        const new_block = try self.allocator.alloc(u8, self.size);
        try self.blocks.append(new_block);
        self.current_block = self.blocks.items.len - 1;
        self.current_pos = size;
        return new_block[0..size];
    }

    pub fn reset(self: *Self) void {
        self.current_block = 0;
        self.current_pos = 0;
    }
};

/// Callback function type for parsing
pub const ParseCallback = fn (Token) anyerror!void;

/// Main streaming parser engine
pub const StreamingParser = struct {
    const Self = @This();

    /// Configuration
    config: ParserConfig,

    /// SIMD parser
    simd_parser: SimdParser,

    /// Memory pool for temporary allocations
    memory_pool: MemoryPool,

    /// Current token stream
    token_stream: ?TokenStream = null,

    /// Input data
    input_data: []const u8 = "",

    pub fn init(allocator: Allocator, config: ParserConfig) !Self {
        const builtin = @import("builtin");
        const simd_parser = SimdParser.init(builtin.target);
        const memory_pool = MemoryPool.init(allocator, config.memory_pool_size);

        return Self{
            .config = config,
            .simd_parser = simd_parser,
            .memory_pool = memory_pool,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.token_stream) |*stream| {
            stream.deinit();
        }
        self.memory_pool.deinit();
    }

    pub fn parseStream(
        self: *Self,
        input: []const u8,
        callback: ParseCallback,
    ) !void {
        self.input_data = input;

        // Initialize token stream if zero-copy is enabled
        if (self.config.zero_copy_tokens) {
            if (self.token_stream) |*stream| {
                stream.deinit();
            }
            self.token_stream = TokenStream.init(self.memory_pool.allocator, input);
        }

        // Parse in chunks
        var offset: usize = 0;
        while (offset < input.len) {
            const chunk_size = @min(self.config.chunk_size, input.len - offset);
            const chunk = input[offset .. offset + chunk_size];

            try self.simd_parser.parseChunk(chunk, callback);
            offset += chunk_size;
        }
    }

    pub fn getTokenStream(self: *Self) ?*TokenStream {
        if (self.token_stream) |*stream| {
            return stream;
        }
        return null;
    }

    pub fn parseStreaming(self: *Self, input: []const u8) !TokenStream {
        self.input_data = input;
        
        var token_stream = TokenStream.init(self.memory_pool.allocator, input);
        
        // Use parseStream with a callback that adds tokens to our stream
        const StreamCallback = struct {
            var current_stream: ?*TokenStream = null;
            
            fn callback(token: Token) anyerror!void {
                if (current_stream) |stream| {
                    try stream.addToken(token);
                }
            }
        };
        
        // Set the current stream for the callback
        StreamCallback.current_stream = &token_stream;
        defer StreamCallback.current_stream = null;
        
        // Use parseStream which properly handles chunking and callbacks
        try self.parseStream(input, StreamCallback.callback);
        
        return token_stream;
    }

    pub fn reset(self: *Self) void {
        self.memory_pool.reset();
        if (self.token_stream) |*stream| {
            stream.reset();
        }
    }
};

test "StreamingParser basic functionality" {
    const allocator = std.testing.allocator;

    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();

    const json = "{\"name\":\"test\",\"value\":42}";
    var token_count: usize = 0;

    const CallbackContext = struct {
        count: *usize,
        fn callback(self: @This(), token: Token) error{}!void {
            self.count.* += 1;
            _ = token;
        }
    };

    const context = CallbackContext{ .count = &token_count };
    try parser.parseStream(json, context.callback);

    try std.testing.expect(token_count > 0);
}

test "TokenStream zero-copy functionality" {
    const allocator = std.testing.allocator;

    const input_data = "{\"test\":\"value\"}";
    var stream = TokenStream.init(allocator, input_data);
    defer stream.deinit();

    try stream.addToken(Token.init(.object_start, 0, 1, 1, 1));
    try stream.addToken(Token.init(.string, 1, 7, 1, 2));
    try stream.addToken(Token.init(.colon, 7, 8, 1, 8));
    try stream.addToken(Token.init(.string, 8, 15, 1, 9));
    try stream.addToken(Token.init(.object_end, 15, 16, 1, 16));

    try std.testing.expectEqual(@as(usize, 5), stream.getTokenCount());

    const first_token = stream.getToken(0);
    try std.testing.expect(first_token != null);
    try std.testing.expectEqual(TokenType.object_start, first_token.?.token_type);

    const string_value = stream.getTokenValue(stream.getToken(1).?);
    try std.testing.expect(string_value != null);
    try std.testing.expectEqualStrings("\"test\"", string_value.?);
}
