const std = @import("std");
const types = @import("../minifier/types.zig");

pub const StreamingValidator = struct {
    // Validation state
    state: ValidationState,
    context_stack: [32]types.Context,
    context_depth: u8,

    // Error tracking
    errors: std.ArrayList(ValidationError),
    warnings: std.ArrayList(ValidationWarning),

    // Statistics
    bytes_processed: u64,
    objects_count: u64,
    arrays_count: u64,
    strings_count: u64,
    numbers_count: u64,
    booleans_count: u64,
    nulls_count: u64,

    // Performance tracking
    validation_start_time: i64,
    validation_overhead_ns: u64,

    allocator: std.mem.Allocator,

    const ValidationState = enum {
        Valid,
        Invalid,
        Warning,
    };

    const ValidationError = struct {
        position: u64,
        message: []const u8,
        severity: ErrorSeverity,
        context: []const u8,

        pub fn deinit(self: *ValidationError, allocator: std.mem.Allocator) void {
            allocator.free(self.message);
            allocator.free(self.context);
        }
    };

    const ValidationWarning = struct {
        position: u64,
        message: []const u8,
        suggestion: []const u8,

        pub fn deinit(self: *ValidationWarning, allocator: std.mem.Allocator) void {
            allocator.free(self.message);
            allocator.free(self.suggestion);
        }
    };

    const ErrorSeverity = enum {
        Fatal,
        Error,
        Warning,
    };

    pub fn init(allocator: std.mem.Allocator) StreamingValidator {
        var validator = StreamingValidator{
            .state = .Valid,
            .context_stack = undefined,
            .context_depth = 0,
            .errors = std.ArrayList(ValidationError).init(allocator),
            .warnings = std.ArrayList(ValidationWarning).init(allocator),
            .bytes_processed = 0,
            .objects_count = 0,
            .arrays_count = 0,
            .strings_count = 0,
            .numbers_count = 0,
            .booleans_count = 0,
            .nulls_count = 0,
            .validation_start_time = std.time.microTimestamp(),
            .validation_overhead_ns = 0,
            .allocator = allocator,
        };

        validator.context_stack[0] = .TopLevel;
        validator.context_depth = 1;

        return validator;
    }

    pub fn deinit(self: *StreamingValidator) void {
        // Clean up errors
        for (self.errors.items) |*validation_error| {
            validation_error.deinit(self.allocator);
        }
        self.errors.deinit();

        // Clean up warnings
        for (self.warnings.items) |*warn| {
            warn.deinit(self.allocator);
        }
        self.warnings.deinit();
    }

    pub fn validateAndMinify(self: *StreamingValidator, input: []const u8, writer: std.io.AnyWriter) !void {
        const start_time = std.time.nanoTimestamp();

        var parser = try types.MinifyingParser.init(self.allocator, writer);
        defer parser.deinit(self.allocator);

        var pos: usize = 0;
        while (pos < input.len) {
            const byte = input[pos];

            // Validate byte
            self.validateByte(byte, pos) catch {
                // Log validation error but continue processing
            };

            // Feed to minifier
            try parser.feedByte(byte);

            pos += 1;
            self.bytes_processed += 1;
        }

        try parser.flush();

        // Final validation
        self.validateComplete() catch {
            // Log validation error but continue
        };

        const end_time = std.time.nanoTimestamp();
        self.validation_overhead_ns = @as(u64, @intCast(end_time - start_time));
    }

    pub fn validateByte(self: *StreamingValidator, byte: u8, position: usize) !void {
        // Validate based on current context
        const context = self.getCurrentContext();

        switch (context) {
            .TopLevel => try self.validateTopLevel(byte, position),
            .Object => try self.validateObject(byte, position),
            .Array => try self.validateArray(byte, position),
        }
    }

    fn validateTopLevel(self: *StreamingValidator, byte: u8, position: usize) !void {
        if (byte == '{') {
            try self.pushContext(.Object);
            self.objects_count += 1;
        } else if (byte == '[') {
            try self.pushContext(.Array);
            self.arrays_count += 1;
        } else if (!self.isWhitespace(byte)) {
            try self.addError(position, "Invalid character at top level", .Fatal, "Expected object or array start");
        }
    }

    fn validateObject(self: *StreamingValidator, byte: u8, _: usize) !void {
        if (byte == '"') {
            self.strings_count += 1;
        } else if (byte == '}') {
            _ = self.popContext();
        } else if (byte == '{') {
            try self.pushContext(.Object);
            self.objects_count += 1;
        } else if (byte == '[') {
            try self.pushContext(.Array);
            self.arrays_count += 1;
        } else if (byte >= '0' and byte <= '9') {
            self.numbers_count += 1;
        } else if (byte == 't' or byte == 'f') {
            // Could be true/false
            self.booleans_count += 1;
        } else if (byte == 'n') {
            // Could be null
            self.nulls_count += 1;
        }
    }

    fn validateArray(self: *StreamingValidator, byte: u8, _: usize) !void {
        if (byte == ']') {
            _ = self.popContext();
        } else if (byte == '{') {
            try self.pushContext(.Object);
            self.objects_count += 1;
        } else if (byte == '[') {
            try self.pushContext(.Array);
            self.arrays_count += 1;
        } else if (byte == '"') {
            self.strings_count += 1;
        } else if (byte >= '0' and byte <= '9') {
            self.numbers_count += 1;
        } else if (byte == 't' or byte == 'f') {
            self.booleans_count += 1;
        } else if (byte == 'n') {
            self.nulls_count += 1;
        }
    }

    pub fn validateComplete(self: *StreamingValidator) !void {
        if (self.context_depth > 1) {
            try self.addError(self.bytes_processed, "Unclosed structures", .Fatal, "Missing closing braces/brackets");
        }

        // Check for common issues
        if (self.objects_count == 0 and self.arrays_count == 0) {
            try self.addWarning(0, "Empty JSON document", "Consider adding content");
        }

        if (self.strings_count > 10000) {
            try self.addWarning(0, "Large number of strings", "Consider using string pooling");
        }

        if (self.objects_count > 1000) {
            try self.addWarning(0, "Large number of objects", "Consider breaking into smaller documents");
        }

        if (self.arrays_count > 1000) {
            try self.addWarning(0, "Large number of arrays", "Consider pagination or streaming");
        }
    }

    fn pushContext(self: *StreamingValidator, context: types.Context) !void {
        if (self.context_depth >= self.context_stack.len) {
            return error.NestingTooDeep;
        }
        self.context_stack[self.context_depth] = context;
        self.context_depth += 1;
    }

    fn popContext(self: *StreamingValidator) ?types.Context {
        if (self.context_depth == 0) return null;
        self.context_depth -= 1;
        return self.context_stack[self.context_depth];
    }

    fn getCurrentContext(self: *StreamingValidator) types.Context {
        if (self.context_depth == 0) return .TopLevel;
        return self.context_stack[self.context_depth - 1];
    }

    fn addError(self: *StreamingValidator, position: usize, message: []const u8, severity: ErrorSeverity, context: []const u8) !void {
        const error_msg = try self.allocator.dupe(u8, message);
        const context_msg = try self.allocator.dupe(u8, context);
        try self.errors.append(.{
            .position = position,
            .message = error_msg,
            .severity = severity,
            .context = context_msg,
        });

        if (severity == .Fatal) {
            self.state = .Invalid;
        }
    }

    fn addWarning(self: *StreamingValidator, position: usize, message: []const u8, suggestion: []const u8) !void {
        const error_msg = try self.allocator.dupe(u8, message);
        const suggestion_msg = try self.allocator.dupe(u8, suggestion);
        try self.warnings.append(.{
            .position = position,
            .message = error_msg,
            .suggestion = suggestion_msg,
        });
    }

    fn isWhitespace(_: *StreamingValidator, byte: u8) bool {
        return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r';
    }

    pub fn getValidationReport(self: *StreamingValidator) ValidationReport {
        return ValidationReport{
            .is_valid = self.state == .Valid,
            .error_count = self.errors.items.len,
            .warning_count = self.warnings.items.len,
            .bytes_processed = self.bytes_processed,
            .objects_count = self.objects_count,
            .arrays_count = self.arrays_count,
            .strings_count = self.strings_count,
            .numbers_count = self.numbers_count,
            .booleans_count = self.booleans_count,
            .nulls_count = self.nulls_count,
            .validation_overhead_ns = self.validation_overhead_ns,
            .validation_time_ms = @as(f64, @floatFromInt(self.validation_overhead_ns)) / 1_000_000.0,
        };
    }

    pub fn printErrors(self: *StreamingValidator, writer: std.io.AnyWriter) !void {
        if (self.errors.items.len == 0) {
            try writer.writeAll("No validation errors found.\n");
            return;
        }

        try writer.print("Found {} validation errors:\n", .{self.errors.items.len});

        for (self.errors.items, 0..) |err, i| {
            try writer.print("  {}. Error at position {}: {s}\n", .{ i + 1, err.position, err.message });
            if (err.context.len > 0) {
                try writer.print("     Context: {s}\n", .{err.context});
            }
        }
    }

    pub fn printWarnings(self: *StreamingValidator, writer: std.io.AnyWriter) !void {
        if (self.warnings.items.len == 0) {
            try writer.writeAll("No validation warnings found.\n");
            return;
        }

        try writer.print("Found {} validation warnings:\n", .{self.warnings.items.len});

        for (self.warnings.items, 0..) |warn, i| {
            try writer.print("  {}. Warning at position {}: {s}\n", .{ i + 1, warn.position, warn.message });
            if (warn.suggestion.len > 0) {
                try writer.print("     Suggestion: {s}\n", .{warn.suggestion});
            }
        }
    }

    const ValidationReport = struct {
        is_valid: bool,
        error_count: usize,
        warning_count: usize,
        bytes_processed: u64,
        objects_count: u64,
        arrays_count: u64,
        strings_count: u64,
        numbers_count: u64,
        booleans_count: u64,
        nulls_count: u64,
        validation_overhead_ns: u64,
        validation_time_ms: f64,
    };
};
