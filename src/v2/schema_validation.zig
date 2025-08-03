const std = @import("std");
const Allocator = std.mem.Allocator;
const Token = @import("streaming/parser.zig").Token;
const TokenType = @import("streaming/parser.zig").TokenType;
const TokenStream = @import("streaming/parser.zig").TokenStream;
const ErrorContext = @import("error_handling.zig").ErrorContext;
const ErrorType = @import("error_handling.zig").ErrorType;

/// JSON Schema validation implementation
/// Supports JSON Schema Draft-07 and Draft-2020-12 features

/// Schema types supported
pub const SchemaType = enum {
    null,
    boolean,
    integer,
    number,
    string,
    array,
    object,
    any, // No type constraint
};

/// String format validation types
pub const StringFormat = enum {
    none,
    email,
    uri,
    uri_reference,
    uuid,
    date,
    date_time,
    time,
    ipv4,
    ipv6,
    hostname,
    json_pointer,
    regex,
};

/// Validation error details
pub const ValidationError = struct {
    /// Error message
    message: []const u8,
    
    /// Path to the invalid data (JSON Pointer format)
    instance_path: []const u8,
    
    /// Path to the schema that failed
    schema_path: []const u8,
    
    /// Position in input where error occurred
    position: usize,
    
    /// Expected value or constraint
    expected: ?[]const u8 = null,
    
    /// Actual value that failed validation
    actual: ?[]const u8 = null,
};

/// Schema validation configuration
pub const ValidationConfig = struct {
    /// Schema draft version to support
    draft: enum { draft_07, draft_2020_12 } = .draft_07,
    
    /// Stop validation on first error
    fail_fast: bool = false,
    
    /// Maximum validation errors to collect
    max_errors: usize = 100,
    
    /// Enable format validation for strings
    validate_formats: bool = true,
    
    /// Enable remote schema reference resolution
    allow_remote_refs: bool = false,
    
    /// Default schema for unspecified properties
    additional_properties: bool = true,
    
    /// Strict mode (no undefined behavior)
    strict_mode: bool = false,
};

/// JSON Schema definition
pub const Schema = struct {
    const Self = @This();
    
    allocator: Allocator,
    
    // Core schema properties
    schema_type: ?SchemaType = null,
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    default: ?[]const u8 = null,
    examples: ?[][]const u8 = null,
    
    // Type-specific constraints
    
    // String constraints
    min_length: ?usize = null,
    max_length: ?usize = null,
    pattern: ?[]const u8 = null, // Regular expression
    format: StringFormat = .none,
    
    // Number constraints  
    minimum: ?f64 = null,
    maximum: ?f64 = null,
    exclusive_minimum: ?f64 = null,
    exclusive_maximum: ?f64 = null,
    multiple_of: ?f64 = null,
    
    // Array constraints
    min_items: ?usize = null,
    max_items: ?usize = null,
    unique_items: bool = false,
    items: ?*Schema = null, // Schema for array items
    prefix_items: ?[]*Schema = null, // Tuple validation
    
    // Object constraints
    min_properties: ?usize = null,
    max_properties: ?usize = null,
    required: ?[]const []const u8 = null,
    properties: ?std.StringHashMap(*Schema) = null,
    pattern_properties: ?std.StringHashMap(*Schema) = null,
    additional_properties_schema: ?*Schema = null,
    property_names: ?*Schema = null,
    
    // Composition
    all_of: ?[]*Schema = null,
    any_of: ?[]*Schema = null,
    one_of: ?[]*Schema = null,
    not: ?*Schema = null,
    
    // Conditional
    if_schema: ?*Schema = null,
    then_schema: ?*Schema = null,
    else_schema: ?*Schema = null,
    
    // References
    ref: ?[]const u8 = null, // $ref
    id: ?[]const u8 = null, // $id
    
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.properties) |*props| {
            var it = props.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.*.deinit();
                self.allocator.destroy(entry.value_ptr.*);
            }
            props.deinit();
        }
        
        if (self.items) |item_schema| {
            item_schema.deinit();
            self.allocator.destroy(item_schema);
        }
        
        if (self.prefix_items) |items| {
            for (items) |item| {
                item.deinit();
                self.allocator.destroy(item);
            }
            self.allocator.free(items);
        }
        
        // Clean up composition schemas
        if (self.all_of) |schemas| {
            for (schemas) |schema| {
                schema.deinit();
                self.allocator.destroy(schema);
            }
            self.allocator.free(schemas);
        }
        
        if (self.any_of) |schemas| {
            for (schemas) |schema| {
                schema.deinit();
                self.allocator.destroy(schema);
            }
            self.allocator.free(schemas);
        }
        
        if (self.one_of) |schemas| {
            for (schemas) |schema| {
                schema.deinit();
                self.allocator.destroy(schema);
            }
            self.allocator.free(schemas);
        }
        
        if (self.not) |not_schema| {
            not_schema.deinit();
            self.allocator.destroy(not_schema);
        }
    }
    
    /// Parse schema from JSON string
    pub fn fromJson(allocator: Allocator, json: []const u8) !*Self {
        // This would be a full JSON Schema parser
        // For now, return a simple schema
        const schema = try allocator.create(Self);
        schema.* = Self.init(allocator);
        
        // TODO: Implement full JSON Schema parsing
        // This is a placeholder that would parse the JSON and populate the schema
        _ = json;
        
        return schema;
    }
    
    /// Create a simple type-based schema
    pub fn forType(allocator: Allocator, schema_type: SchemaType) !*Self {
        const schema = try allocator.create(Self);
        schema.* = Self.init(allocator);
        schema.schema_type = schema_type;
        return schema;
    }
    
    /// Create schema for string with constraints
    pub fn forString(
        allocator: Allocator,
        min_len: ?usize,
        max_len: ?usize,
        format: StringFormat,
    ) !*Self {
        const schema = try allocator.create(Self);
        schema.* = Self.init(allocator);
        schema.schema_type = .string;
        schema.min_length = min_len;
        schema.max_length = max_len;
        schema.format = format;
        return schema;
    }
    
    /// Create schema for number with constraints
    pub fn forNumber(
        allocator: Allocator,
        minimum: ?f64,
        maximum: ?f64,
        multiple_of: ?f64,
    ) !*Self {
        const schema = try allocator.create(Self);
        schema.* = Self.init(allocator);
        schema.schema_type = .number;
        schema.minimum = minimum;
        schema.maximum = maximum;
        schema.multiple_of = multiple_of;
        return schema;
    }
    
    /// Create schema for object with required properties
    pub fn forObject(
        allocator: Allocator,
        required_props: ?[]const []const u8,
    ) !*Self {
        const schema = try allocator.create(Self);
        schema.* = Self.init(allocator);
        schema.schema_type = .object;
        schema.required = required_props;
        schema.properties = std.StringHashMap(*Schema).init(allocator);
        return schema;
    }
    
    /// Add property schema to object schema
    pub fn addProperty(self: *Self, name: []const u8, property_schema: *Schema) !void {
        if (self.properties == null) {
            self.properties = std.StringHashMap(*Schema).init(self.allocator);
        }
        try self.properties.?.put(name, property_schema);
    }
};

/// Validator state during streaming validation
pub const ValidatorState = struct {
    const Self = @This();
    
    allocator: Allocator,
    config: ValidationConfig,
    errors: std.ArrayList(ValidationError),
    
    // Current validation context
    path_stack: std.ArrayList([]const u8), // JSON pointer path
    schema_stack: std.ArrayList(*Schema),
    object_properties: std.ArrayList(std.StringHashMap(bool)), // Track seen properties
    
    // Statistics
    nodes_validated: usize = 0,
    max_depth: usize = 0,
    
    pub fn init(allocator: Allocator, config: ValidationConfig) Self {
        return .{
            .allocator = allocator,
            .config = config,
            .errors = std.ArrayList(ValidationError).init(allocator),
            .path_stack = std.ArrayList([]const u8).init(allocator),
            .schema_stack = std.ArrayList(*Schema).init(allocator),
            .object_properties = std.ArrayList(std.StringHashMap(bool)).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.errors.deinit();
        self.path_stack.deinit();
        self.schema_stack.deinit();
        for (self.object_properties.items) |*props| {
            props.deinit();
        }
        self.object_properties.deinit();
    }
    
    pub fn getErrors(self: *const Self) []const ValidationError {
        return self.errors.items;
    }
    
    pub fn isValid(self: *const Self) bool {
        return self.errors.items.len == 0;
    }
    
    pub fn getCurrentPath(self: *const Self) ![]u8 {
        var path = std.ArrayList(u8).init(self.allocator);
        defer path.deinit();
        
        for (self.path_stack.items) |segment| {
            try path.append('/');
            try path.appendSlice(segment);
        }
        
        if (path.items.len == 0) {
            try path.append('/');
        }
        
        return self.allocator.dupe(u8, path.items);
    }
    
    pub fn addError(
        self: *Self,
        message: []const u8,
        position: usize,
        expected: ?[]const u8,
        actual: ?[]const u8,
    ) !void {
        if (self.errors.items.len >= self.config.max_errors) {
            return;
        }
        
        const instance_path = try self.getCurrentPath();
        
        const error_info = ValidationError{
            .message = message,
            .instance_path = instance_path,
            .schema_path = "/", // TODO: Implement schema path tracking
            .position = position,
            .expected = expected,
            .actual = actual,
        };
        
        try self.errors.append(error_info);
        
        if (self.config.fail_fast) {
            return error.ValidationFailed;
        }
    }
};

/// Schema validator for streaming JSON
pub const SchemaValidator = struct {
    const Self = @This();
    
    allocator: Allocator,
    schema: *Schema,
    config: ValidationConfig,
    
    pub fn init(allocator: Allocator, schema: *Schema, config: ValidationConfig) Self {
        return .{
            .allocator = allocator,
            .schema = schema,
            .config = config,
        };
    }
    
    /// Validate a token stream against the schema
    pub fn validateTokenStream(
        self: *Self,
        token_stream: *const TokenStream,
    ) !ValidatorState {
        var state = ValidatorState.init(self.allocator, self.config);
        errdefer state.deinit();
        
        // Push root schema
        try state.schema_stack.append(self.schema);
        
        var stream_copy = token_stream.*;
        stream_copy.reset();
        
        while (stream_copy.hasMore()) {
            const token = stream_copy.getCurrentToken() orelse {
                stream_copy.advance();
                continue;
            };
            
            try self.validateToken(&state, token, token_stream.input_data);
            stream_copy.advance();
        }
        
        // Validate required properties for objects
        try self.validateRequiredProperties(&state);
        
        return state;
    }
    
    fn validateToken(
        self: *Self,
        state: *ValidatorState,
        token: Token,
        input_data: []const u8,
    ) !void {
        state.nodes_validated += 1;
        
        if (state.schema_stack.items.len == 0) {
            return; // No schema to validate against
        }
        
        const current_schema = state.schema_stack.items[state.schema_stack.items.len - 1];
        
        switch (token.token_type) {
            .object_start => {
                try self.validateObjectStart(state, current_schema, token);
            },
            .object_end => {
                try self.validateObjectEnd(state);
            },
            .array_start => {
                try self.validateArrayStart(state, current_schema, token);
            },
            .array_end => {
                try self.validateArrayEnd(state);
            },
            .string => {
                const value = input_data[token.start..token.end];
                try self.validateString(state, current_schema, value, token);
            },
            .number => {
                const value = input_data[token.start..token.end];
                try self.validateNumber(state, current_schema, value, token);
            },
            .boolean_true, .boolean_false => {
                try self.validateBoolean(state, current_schema, token);
            },
            .null => {
                try self.validateNull(state, current_schema, token);
            },
            else => {
                // Skip other token types
            },
        }
    }
    
    fn validateObjectStart(
        self: *Self,
        state: *ValidatorState,
        schema: *Schema,
        token: Token,
    ) !void {
        // Check if object is allowed by schema
        if (schema.schema_type) |schema_type| {
            if (schema_type != .object and schema_type != .any) {
                try state.addError(
                    "Expected type does not match",
                    token.start,
                    @tagName(schema_type),
                    "object",
                );
                return;
            }
        }
        
        // Initialize property tracking
        try state.object_properties.append(std.StringHashMap(bool).init(self.allocator));
        
        // Update max depth tracking
        state.max_depth = @max(state.max_depth, state.path_stack.items.len);
    }
    
    fn validateObjectEnd(_: *Self, state: *ValidatorState) !void {
        
        // Pop property tracking
        if (state.object_properties.items.len > 0) {
            var props = state.object_properties.pop();
            props.deinit();
        }
        
        // Pop schema if needed
        if (state.schema_stack.items.len > 1) {
            _ = state.schema_stack.pop();
        }
    }
    
    fn validateArrayStart(
        _: *Self,
        state: *ValidatorState,
        schema: *Schema,
        token: Token,
    ) !void {
        // Check if array is allowed by schema
        if (schema.schema_type) |schema_type| {
            if (schema_type != .array and schema_type != .any) {
                try state.addError(
                    "Expected type does not match",
                    token.start,
                    @tagName(schema_type),
                    "array",
                );
                return;
            }
        }
        
        // Push item schema if available
        if (schema.items) |item_schema| {
            try state.schema_stack.append(item_schema);
        }
    }
    
    fn validateArrayEnd(_: *Self, state: *ValidatorState) !void {
        
        // Pop item schema if it was pushed
        if (state.schema_stack.items.len > 1) {
            _ = state.schema_stack.pop();
        }
    }
    
    fn validateString(
        self: *Self,
        state: *ValidatorState,
        schema: *Schema,
        value: []const u8,
        token: Token,
    ) !void {
        // Check type
        if (schema.schema_type) |schema_type| {
            if (schema_type != .string and schema_type != .any) {
                try state.addError(
                    "Expected type does not match",
                    token.start,
                    @tagName(schema_type),
                    "string",
                );
                return;
            }
        }
        
        // Remove quotes for validation
        const string_value = if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"')
            value[1..value.len - 1]
        else
            value;
        
        // Validate length constraints
        if (schema.min_length) |min_len| {
            if (string_value.len < min_len) {
                try state.addError(
                    "String too short",
                    token.start,
                    null,
                    string_value,
                );
            }
        }
        
        if (schema.max_length) |max_len| {
            if (string_value.len > max_len) {
                try state.addError(
                    "String too long",
                    token.start,
                    null,
                    string_value,
                );
            }
        }
        
        // Validate format if enabled
        if (self.config.validate_formats and schema.format != .none) {
            if (!try self.validateStringFormat(string_value, schema.format)) {
                try state.addError(
                    "String format validation failed",
                    token.start,
                    @tagName(schema.format),
                    string_value,
                );
            }
        }
    }
    
    fn validateNumber(
        _: *Self,
        state: *ValidatorState,
        schema: *Schema,
        value: []const u8,
        token: Token,
    ) !void {
        // Check type
        if (schema.schema_type) |schema_type| {
            if (schema_type != .number and schema_type != .integer and schema_type != .any) {
                try state.addError(
                    "Expected type does not match",
                    token.start,
                    @tagName(schema_type),
                    "number",
                );
                return;
            }
        }
        
        const number = std.fmt.parseFloat(f64, value) catch {
            try state.addError(
                "Invalid number format",
                token.start,
                "valid number",
                value,
            );
            return;
        };
        
        // Validate range constraints
        if (schema.minimum) |min| {
            if (number < min) {
                try state.addError(
                    "Number below minimum",
                    token.start,
                    null,
                    value,
                );
            }
        }
        
        if (schema.maximum) |max| {
            if (number > max) {
                try state.addError(
                    "Number above maximum",
                    token.start,
                    null,
                    value,
                );
            }
        }
        
        if (schema.exclusive_minimum) |min| {
            if (number <= min) {
                try state.addError(
                    "Number not above exclusive minimum",
                    token.start,
                    null,
                    value,
                );
            }
        }
        
        if (schema.exclusive_maximum) |max| {
            if (number >= max) {
                try state.addError(
                    "Number not below exclusive maximum",
                    token.start,
                    null,
                    value,
                );
            }
        }
        
        if (schema.multiple_of) |multiple| {
            const remainder = @mod(number, multiple);
            if (remainder != 0.0) {
                try state.addError(
                    "Number is not a multiple of constraint",
                    token.start,
                    null,
                    value,
                );
            }
        }
        
        // Check integer constraint
        if (schema.schema_type == .integer) {
            if (@floor(number) != number) {
                try state.addError(
                    "Expected integer, got decimal",
                    token.start,
                    "integer",
                    value,
                );
            }
        }
    }
    
    fn validateBoolean(
        _: *Self,
        state: *ValidatorState,
        schema: *Schema,
        token: Token,
    ) !void {
        
        if (schema.schema_type) |schema_type| {
            if (schema_type != .boolean and schema_type != .any) {
                try state.addError(
                    "Expected type does not match",
                    token.start,
                    @tagName(schema_type),
                    "boolean",
                );
            }
        }
    }
    
    fn validateNull(
        _: *Self,
        state: *ValidatorState,
        schema: *Schema,
        token: Token,
    ) !void {
        
        if (schema.schema_type) |schema_type| {
            if (schema_type != .null and schema_type != .any) {
                try state.addError(
                    "Expected type does not match",
                    token.start,
                    @tagName(schema_type),
                    "null",
                );
            }
        }
    }
    
    fn validateRequiredProperties(self: *Self, state: *ValidatorState) !void {
        // TODO: Implement required property validation
        // This would check that all required properties were seen during object validation
        _ = self;
        _ = state;
    }
    
    pub fn validateStringFormat(self: *Self, value: []const u8, format: StringFormat) !bool {
        return switch (format) {
            .none => true,
            .email => self.isValidEmail(value),
            .uri => self.isValidUri(value),
            .uuid => self.isValidUuid(value),
            .date => self.isValidDate(value),
            .date_time => self.isValidDateTime(value),
            .ipv4 => self.isValidIpv4(value),
            .ipv6 => self.isValidIpv6(value),
            else => true, // TODO: Implement other format validations
        };
    }
    
    // Simple format validation functions
    fn isValidEmail(self: *Self, value: []const u8) bool {
        _ = self;
        return std.mem.indexOf(u8, value, "@") != null and value.len > 3;
    }
    
    fn isValidUri(self: *Self, value: []const u8) bool {
        _ = self;
        return std.mem.startsWith(u8, value, "http://") or std.mem.startsWith(u8, value, "https://");
    }
    
    fn isValidUuid(self: *Self, value: []const u8) bool {
        _ = self;
        return value.len == 36 and value[8] == '-' and value[13] == '-';
    }
    
    fn isValidDate(self: *Self, value: []const u8) bool {
        _ = self;
        return value.len == 10 and value[4] == '-' and value[7] == '-';
    }
    
    fn isValidDateTime(self: *Self, value: []const u8) bool {
        _ = self;
        return value.len >= 19 and std.mem.indexOf(u8, value, "T") != null;
    }
    
    fn isValidIpv4(self: *Self, value: []const u8) bool {
        _ = self;
        var parts = std.mem.splitScalar(u8, value, '.');
        var count: usize = 0;
        while (parts.next()) |part| {
            count += 1;
            if (count > 4) return false;
            const num = std.fmt.parseInt(u8, part, 10) catch return false;
            _ = num; // All u8 values are valid for IPv4 octets
        }
        return count == 4;
    }
    
    fn isValidIpv6(self: *Self, value: []const u8) bool {
        _ = self;
        return std.mem.indexOf(u8, value, ":") != null and value.len >= 2;
    }
};

// Tests
test "Schema creation and basic validation" {
    const allocator = std.testing.allocator;
    
    // Create a simple string schema
    var string_schema = try Schema.forString(allocator, 5, 50, .email);
    defer {
        string_schema.deinit();
        allocator.destroy(string_schema);
    }
    
    try std.testing.expect(string_schema.schema_type.? == .string);
    try std.testing.expect(string_schema.min_length.? == 5);
    try std.testing.expect(string_schema.max_length.? == 50);
    try std.testing.expect(string_schema.format == .email);
}

test "Number schema validation" {
    const allocator = std.testing.allocator;
    
    var number_schema = try Schema.forNumber(allocator, 0, 100, 5);
    defer {
        number_schema.deinit();
        allocator.destroy(number_schema);
    }
    
    try std.testing.expect(number_schema.schema_type.? == .number);
    try std.testing.expect(number_schema.minimum.? == 0);
    try std.testing.expect(number_schema.maximum.? == 100);
    try std.testing.expect(number_schema.multiple_of.? == 5);
}

test "Object schema with properties" {
    const allocator = std.testing.allocator;
    
    const required = [_][]const u8{"name", "age"};
    var object_schema = try Schema.forObject(allocator, &required);
    defer {
        object_schema.deinit();
        allocator.destroy(object_schema);
    }
    
    // Add property schemas
    const name_schema = try Schema.forString(allocator, 1, 50, .none);
    try object_schema.addProperty("name", name_schema);
    
    const age_schema = try Schema.forNumber(allocator, 0, 150, null);
    try object_schema.addProperty("age", age_schema);
    
    try std.testing.expect(object_schema.schema_type.? == .object);
    try std.testing.expect(object_schema.required != null);
    try std.testing.expect(object_schema.required.?.len == 2);
}