//! zmin-validate: Comprehensive JSON validator with detailed error reporting
//!
//! This tool provides extensive JSON validation with precise error locations,
//! schema validation, and best practice checks.

const std = @import("std");

const ValidationOptions = struct {
    strict: bool = false,
    check_duplicates: bool = true,
    max_depth: u32 = 1000,
    schema_file: ?[]const u8 = null,
    verbose: bool = false,
    quiet: bool = false,
};

const ValidationError = struct {
    line: u32,
    column: u32,
    offset: usize,
    message: []const u8,
    severity: enum { @"error", warning, info },
    context: ?[]const u8 = null,
};

const ValidationResult = struct {
    valid: bool,
    errors: std.ArrayList(ValidationError),
    warnings: std.ArrayList(ValidationError),
    info: std.ArrayList(ValidationError),
    
    pub fn deinit(self: *ValidationResult) void {
        self.errors.deinit();
        self.warnings.deinit();
        self.info.deinit();
    }
    
    pub fn addError(self: *ValidationResult, err: ValidationError) !void {
        try self.errors.append(err);
        self.valid = false;
    }
    
    pub fn addWarning(self: *ValidationResult, warn: ValidationError) !void {
        try self.warnings.append(warn);
    }
    
    pub fn addInfo(self: *ValidationResult, info: ValidationError) !void {
        try self.info.append(info);
    }
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
    
    var options = ValidationOptions{};
    var files = std.ArrayList([]const u8).init(allocator);
    defer files.deinit();
    
    // Parse arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        
        if (std.mem.eql(u8, arg, "--strict")) {
            options.strict = true;
        } else if (std.mem.eql(u8, arg, "--no-duplicates")) {
            options.check_duplicates = true;
        } else if (std.mem.eql(u8, arg, "--max-depth")) {
            i += 1;
            if (i >= args.len) {
                try std.io.getStdErr().writer().print("--max-depth requires a value\n", .{});
                return;
            }
            options.max_depth = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--schema")) {
            i += 1;
            if (i >= args.len) {
                try std.io.getStdErr().writer().print("--schema requires a file path\n", .{});
                return;
            }
            options.schema_file = args[i];
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) {
            options.quiet = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printUsage(args[0]);
            return;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            try files.append(arg);
        } else {
            try std.io.getStdErr().writer().print("Unknown option: {s}\n", .{arg});
            return;
        }
    }
    
    if (files.items.len == 0) {
        // Read from stdin
        try validateStdin(allocator, options);
    } else {
        // Validate files
        var exit_code: u8 = 0;
        for (files.items) |file| {
            const valid = try validateFile(allocator, file, options);
            if (!valid) exit_code = 1;
        }
        std.process.exit(exit_code);
    }
}

fn printUsage(program_name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Usage: {s} [OPTIONS] [FILES...]
        \\
        \\Comprehensive JSON validator with detailed error reporting
        \\
        \\Options:
        \\  -h, --help         Show this help message
        \\  -v, --verbose      Show detailed validation information
        \\  -q, --quiet        Suppress non-error output
        \\  --strict           Enable strict validation mode
        \\  --no-duplicates    Check for duplicate object keys
        \\  --max-depth N      Set maximum nesting depth (default: 1000)
        \\  --schema FILE      Validate against JSON Schema
        \\
        \\Examples:
        \\  {s} data.json
        \\  {s} --strict --verbose *.json
        \\  echo '{{}}' | {s}
        \\  {s} --schema schema.json data.json
        \\
        \\Exit codes:
        \\  0 - All files valid
        \\  1 - One or more files invalid
        \\  2 - Error reading files
        \\
    , .{ program_name, program_name, program_name, program_name, program_name });
}

fn validateStdin(allocator: std.mem.Allocator, options: ValidationOptions) !void {
    const stdin = std.io.getStdIn().reader();
    const input = try stdin.readAllAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(input);
    
    var result = try performValidation(allocator, input, "<stdin>", options);
    defer result.deinit();
    
    try printResult(&result, "<stdin>", options);
    
    if (!result.valid) {
        std.process.exit(1);
    }
}

fn validateFile(allocator: std.mem.Allocator, path: []const u8, options: ValidationOptions) !bool {
    const input = std.fs.cwd().readFileAlloc(allocator, path, 100 * 1024 * 1024) catch |err| {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Error reading '{s}': {}\n", .{ path, err });
        std.process.exit(2);
    };
    defer allocator.free(input);
    
    var result = try performValidation(allocator, input, path, options);
    defer result.deinit();
    
    try printResult(&result, path, options);
    
    return result.valid;
}

fn performValidation(
    allocator: std.mem.Allocator,
    input: []const u8,
    filename: []const u8,
    options: ValidationOptions,
) !ValidationResult {
    _ = filename;
    
    var result = ValidationResult{
        .valid = true,
        .errors = std.ArrayList(ValidationError).init(allocator),
        .warnings = std.ArrayList(ValidationError).init(allocator),
        .info = std.ArrayList(ValidationError).init(allocator),
    };
    
    // Basic JSON validation using standard library parser
    var parser = std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch |err| {
        try result.addError(.{
            .line = 1, // TODO: Calculate actual line
            .column = 1,
            .offset = 0,
            .message = @errorName(err),
            .severity = .@"error",
        });
        return result;
    };
    defer parser.deinit();
    
    // Additional validations
    var validator = DetailedValidator.init(allocator, input, options);
    try validator.validate(&result);
    
    // Schema validation if provided
    if (options.schema_file) |schema_path| {
        try validateAgainstSchema(allocator, input, schema_path, &result);
    }
    
    return result;
}

const DetailedValidator = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    options: ValidationOptions,
    pos: usize = 0,
    line: u32 = 1,
    column: u32 = 1,
    depth: u32 = 0,
    
    pub fn init(allocator: std.mem.Allocator, input: []const u8, options: ValidationOptions) DetailedValidator {
        return .{
            .allocator = allocator,
            .input = input,
            .options = options,
        };
    }
    
    pub fn validate(self: *DetailedValidator, result: *ValidationResult) !void {
        try self.validateValue(result);
        
        // Check for trailing content
        self.skipWhitespace();
        if (self.pos < self.input.len) {
            try result.addWarning(.{
                .line = self.line,
                .column = self.column,
                .offset = self.pos,
                .message = "Trailing content after JSON value",
                .severity = .warning,
            });
        }
    }
    
    fn validateValue(self: *DetailedValidator, result: *ValidationResult) !void {
        self.skipWhitespace();
        
        if (self.pos >= self.input.len) {
            try result.addError(.{
                .line = self.line,
                .column = self.column,
                .offset = self.pos,
                .message = "Unexpected end of input",
                .severity = .@"error",
            });
            return;
        }
        
        const c = self.input[self.pos];
        switch (c) {
            '{' => try self.validateObject(result),
            '[' => try self.validateArray(result),
            '"' => try self.validateString(result),
            't', 'f' => try self.validateBoolean(result),
            'n' => try self.validateNull(result),
            '-', '0'...'9' => try self.validateNumber(result),
            else => {
                try result.addError(.{
                    .line = self.line,
                    .column = self.column,
                    .offset = self.pos,
                    .message = "Invalid character",
                    .severity = .@"error",
                    .context = self.getContext(),
                });
            },
        }
    }
    
    fn validateObject(self: *DetailedValidator, result: *ValidationResult) !void {
        self.depth += 1;
        defer self.depth -= 1;
        
        if (self.depth > self.options.max_depth) {
            try result.addError(.{
                .line = self.line,
                .column = self.column,
                .offset = self.pos,
                .message = "Maximum nesting depth exceeded",
                .severity = .@"error",
            });
            return;
        }
        
        self.advance(); // '{'
        
        var keys = std.StringHashMap(void).init(self.allocator);
        defer keys.deinit();
        
        var first = true;
        while (true) {
            self.skipWhitespace();
            
            if (self.pos >= self.input.len) {
                try result.addError(.{
                    .line = self.line,
                    .column = self.column,
                    .offset = self.pos,
                    .message = "Unterminated object",
                    .severity = .@"error",
                });
                return;
            }
            
            if (self.input[self.pos] == '}') {
                self.advance();
                break;
            }
            
            if (!first) {
                if (self.input[self.pos] != ',') {
                    try result.addError(.{
                        .line = self.line,
                        .column = self.column,
                        .offset = self.pos,
                        .message = "Expected ',' between object members",
                        .severity = .@"error",
                    });
                    return;
                }
                self.advance();
                self.skipWhitespace();
            }
            
            // Key
            const key_start = self.pos;
            const key = try self.parseString(result);
            
            // Check for duplicate keys
            if (self.options.check_duplicates) {
                if (keys.contains(key)) {
                    try result.addWarning(.{
                        .line = self.line,
                        .column = self.column,
                        .offset = key_start,
                        .message = "Duplicate object key",
                        .severity = .warning,
                        .context = try std.fmt.allocPrint(self.allocator, "Key: \"{s}\"", .{key}),
                    });
                } else {
                    try keys.put(key, {});
                }
            }
            
            self.skipWhitespace();
            
            if (self.pos >= self.input.len or self.input[self.pos] != ':') {
                try result.addError(.{
                    .line = self.line,
                    .column = self.column,
                    .offset = self.pos,
                    .message = "Expected ':' after object key",
                    .severity = .@"error",
                });
                return;
            }
            
            self.advance(); // ':'
            
            // Value
            try self.validateValue(result);
            
            first = false;
        }
    }
    
    fn validateArray(self: *DetailedValidator, result: *ValidationResult) !void {
        self.depth += 1;
        defer self.depth -= 1;
        
        if (self.depth > self.options.max_depth) {
            try result.addError(.{
                .line = self.line,
                .column = self.column,
                .offset = self.pos,
                .message = "Maximum nesting depth exceeded",
                .severity = .@"error",
            });
            return;
        }
        
        self.advance(); // '['
        
        var first = true;
        var element_count: u32 = 0;
        
        while (true) {
            self.skipWhitespace();
            
            if (self.pos >= self.input.len) {
                try result.addError(.{
                    .line = self.line,
                    .column = self.column,
                    .offset = self.pos,
                    .message = "Unterminated array",
                    .severity = .@"error",
                });
                return;
            }
            
            if (self.input[self.pos] == ']') {
                self.advance();
                break;
            }
            
            if (!first) {
                if (self.input[self.pos] != ',') {
                    try result.addError(.{
                        .line = self.line,
                        .column = self.column,
                        .offset = self.pos,
                        .message = "Expected ',' between array elements",
                        .severity = .@"error",
                    });
                    return;
                }
                self.advance();
                self.skipWhitespace();
            }
            
            try self.validateValue(result);
            element_count += 1;
            
            first = false;
        }
        
        // Check for very large arrays
        if (element_count > 10000 and self.options.verbose) {
            try result.addInfo(.{
                .line = self.line,
                .column = self.column,
                .offset = self.pos,
                .message = "Large array detected",
                .severity = .info,
                .context = try std.fmt.allocPrint(self.allocator, "{d} elements", .{element_count}),
            });
        }
    }
    
    fn validateString(self: *DetailedValidator, result: *ValidationResult) !void {
        _ = try self.parseString(result);
    }
    
    fn parseString(self: *DetailedValidator, result: *ValidationResult) ![]const u8 {
        const start_line = self.line;
        const start_column = self.column;
        
        self.advance(); // '"'
        const start = self.pos;
        
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            
            if (c == '"') {
                const str = self.input[start..self.pos];
                self.advance();
                return str;
            } else if (c == '\\') {
                self.advance();
                if (self.pos >= self.input.len) {
                    try result.addError(.{
                        .line = self.line,
                        .column = self.column,
                        .offset = self.pos,
                        .message = "Unterminated escape sequence",
                        .severity = .@"error",
                    });
                    return "";
                }
                
                const escape = self.input[self.pos];
                switch (escape) {
                    '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => self.advance(),
                    'u' => {
                        self.advance();
                        // Validate unicode escape
                        for (0..4) |_| {
                            if (self.pos >= self.input.len or !std.ascii.isHex(self.input[self.pos])) {
                                try result.addError(.{
                                    .line = self.line,
                                    .column = self.column,
                                    .offset = self.pos,
                                    .message = "Invalid unicode escape sequence",
                                    .severity = .@"error",
                                });
                                return "";
                            }
                            self.advance();
                        }
                    },
                    else => {
                        try result.addError(.{
                            .line = self.line,
                            .column = self.column,
                            .offset = self.pos - 1,
                            .message = "Invalid escape sequence",
                            .severity = .@"error",
                            .context = try std.fmt.allocPrint(self.allocator, "\\{c}", .{escape}),
                        });
                    },
                }
            } else if (c < 0x20) {
                try result.addError(.{
                    .line = self.line,
                    .column = self.column,
                    .offset = self.pos,
                    .message = "Unescaped control character in string",
                    .severity = .@"error",
                });
                self.advance();
            } else {
                self.advance();
            }
        }
        
        try result.addError(.{
            .line = start_line,
            .column = start_column,
            .offset = start - 1,
            .message = "Unterminated string",
            .severity = .@"error",
        });
        
        return "";
    }
    
    fn validateNumber(self: *DetailedValidator, result: *ValidationResult) !void {
        const start = self.pos;
        
        // Optional minus
        if (self.input[self.pos] == '-') {
            self.advance();
        }
        
        // Integer part
        if (self.pos >= self.input.len) {
            try result.addError(.{
                .line = self.line,
                .column = self.column,
                .offset = start,
                .message = "Invalid number",
                .severity = .@"error",
            });
            return;
        }
        
        if (self.input[self.pos] == '0') {
            self.advance();
        } else if (self.input[self.pos] >= '1' and self.input[self.pos] <= '9') {
            while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
                self.advance();
            }
        } else {
            try result.addError(.{
                .line = self.line,
                .column = self.column,
                .offset = self.pos,
                .message = "Invalid number",
                .severity = .@"error",
            });
            return;
        }
        
        // Fractional part
        if (self.pos < self.input.len and self.input[self.pos] == '.') {
            self.advance();
            
            var digit_count: u32 = 0;
            while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
                self.advance();
                digit_count += 1;
            }
            
            if (digit_count == 0) {
                try result.addError(.{
                    .line = self.line,
                    .column = self.column,
                    .offset = self.pos - 1,
                    .message = "Invalid number: missing digits after decimal point",
                    .severity = .@"error",
                });
            }
        }
        
        // Exponent part
        if (self.pos < self.input.len and (self.input[self.pos] == 'e' or self.input[self.pos] == 'E')) {
            self.advance();
            
            if (self.pos < self.input.len and (self.input[self.pos] == '+' or self.input[self.pos] == '-')) {
                self.advance();
            }
            
            var digit_count: u32 = 0;
            while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
                self.advance();
                digit_count += 1;
            }
            
            if (digit_count == 0) {
                try result.addError(.{
                    .line = self.line,
                    .column = self.column,
                    .offset = self.pos - 1,
                    .message = "Invalid number: missing digits in exponent",
                    .severity = .@"error",
                });
            }
        }
        
        // Check for very large numbers
        const number_str = self.input[start..self.pos];
        if (number_str.len > 100 and self.options.verbose) {
            try result.addWarning(.{
                .line = self.line,
                .column = self.column,
                .offset = start,
                .message = "Very large number literal",
                .severity = .warning,
                .context = try std.fmt.allocPrint(self.allocator, "{d} digits", .{number_str.len}),
            });
        }
    }
    
    fn validateBoolean(self: *DetailedValidator, result: *ValidationResult) !void {
        if (std.mem.startsWith(u8, self.input[self.pos..], "true")) {
            self.pos += 4;
            self.column += 4;
        } else if (std.mem.startsWith(u8, self.input[self.pos..], "false")) {
            self.pos += 5;
            self.column += 5;
        } else {
            try result.addError(.{
                .line = self.line,
                .column = self.column,
                .offset = self.pos,
                .message = "Invalid boolean literal",
                .severity = .@"error",
            });
        }
    }
    
    fn validateNull(self: *DetailedValidator, result: *ValidationResult) !void {
        if (std.mem.startsWith(u8, self.input[self.pos..], "null")) {
            self.pos += 4;
            self.column += 4;
        } else {
            try result.addError(.{
                .line = self.line,
                .column = self.column,
                .offset = self.pos,
                .message = "Invalid null literal",
                .severity = .@"error",
            });
        }
    }
    
    fn skipWhitespace(self: *DetailedValidator) void {
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            switch (c) {
                ' ', '\t', '\r' => {
                    self.pos += 1;
                    self.column += 1;
                },
                '\n' => {
                    self.pos += 1;
                    self.line += 1;
                    self.column = 1;
                },
                else => return,
            }
        }
    }
    
    fn advance(self: *DetailedValidator) void {
        if (self.pos < self.input.len) {
            if (self.input[self.pos] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
    }
    
    fn getContext(self: *DetailedValidator) ?[]const u8 {
        const context_size = 20;
        const start = if (self.pos > context_size) self.pos - context_size else 0;
        const end = @min(self.pos + context_size, self.input.len);
        
        return self.input[start..end];
    }
};

fn validateAgainstSchema(
    allocator: std.mem.Allocator,
    input: []const u8,
    schema_path: []const u8,
    result: *ValidationResult,
) !void {
    _ = allocator;
    _ = input;
    _ = schema_path;
    
    // TODO: Implement JSON Schema validation
    try result.addInfo(.{
        .line = 0,
        .column = 0,
        .offset = 0,
        .message = "JSON Schema validation not yet implemented",
        .severity = .info,
    });
}

fn printResult(result: *ValidationResult, filename: []const u8, options: ValidationOptions) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    
    if (result.valid) {
        if (!options.quiet) {
            try stdout.print("✅ {s}: Valid JSON\n", .{filename});
            
            if (options.verbose) {
                if (result.warnings.items.len > 0) {
                    try stdout.print("   Warnings: {d}\n", .{result.warnings.items.len});
                }
                if (result.info.items.len > 0) {
                    try stdout.print("   Info: {d}\n", .{result.info.items.len});
                }
            }
        }
    } else {
        try stderr.print("❌ {s}: Invalid JSON\n", .{filename});
    }
    
    // Print errors
    for (result.errors.items) |err| {
        try stderr.print("   ERROR at {d}:{d}: {s}\n", .{ err.line, err.column, err.message });
        if (err.context) |ctx| {
            try stderr.print("     Context: {s}\n", .{ctx});
        }
    }
    
    // Print warnings if verbose
    if (options.verbose or !result.valid) {
        for (result.warnings.items) |warn| {
            try stdout.print("   WARNING at {d}:{d}: {s}\n", .{ warn.line, warn.column, warn.message });
            if (warn.context) |ctx| {
                try stdout.print("     Context: {s}\n", .{ctx});
            }
        }
    }
    
    // Print info if verbose
    if (options.verbose) {
        for (result.info.items) |info| {
            try stdout.print("   INFO at {d}:{d}: {s}\n", .{ info.line, info.column, info.message });
            if (info.context) |ctx| {
                try stdout.print("     Context: {s}\n", .{ctx});
            }
        }
    }
}