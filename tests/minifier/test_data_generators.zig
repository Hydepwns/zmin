const std = @import("std");
const testing = std.testing;

/// Generates a large string with repeated characters
pub fn generateLargeString(allocator: std.mem.Allocator, size: usize, char: u8) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, size);
    for (0..size) |_| {
        try result.append(char);
    }
    return result.toOwnedSlice();
}

/// Generates a large JSON string value
pub fn generateLargeJsonString(allocator: std.mem.Allocator, content_size: usize, char: u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    try result.append('"');
    for (0..content_size) |_| {
        try result.append(char);
    }
    try result.append('"');
    return result.toOwnedSlice();
}

/// Generates a deeply nested object structure
pub fn generateNestedObject(allocator: std.mem.Allocator, depth: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    
    // Build opening braces
    for (0..depth) |_| {
        try result.appendSlice("{\"a\":");
    }
    try result.appendSlice("null");
    
    // Build closing braces
    for (0..depth) |_| {
        try result.append('}');
    }
    
    return result.toOwnedSlice();
}

/// Generates a deeply nested array structure
pub fn generateNestedArray(allocator: std.mem.Allocator, depth: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    
    // Build opening brackets
    for (0..depth) |_| {
        try result.append('[');
    }
    try result.appendSlice("null");
    
    // Build closing brackets
    for (0..depth) |_| {
        try result.append(']');
    }
    
    return result.toOwnedSlice();
}

/// Generates a large array with sequential numbers
pub fn generateLargeArray(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    
    try result.append('[');
    for (0..size) |i| {
        if (i > 0) try result.appendSlice(", ");
        try result.writer().print("{}", .{i});
    }
    try result.append(']');
    
    return result.toOwnedSlice();
}

/// Generates a large object with sequential key-value pairs
pub fn generateLargeObject(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    
    try result.append('{');
    for (0..size) |i| {
        if (i > 0) try result.appendSlice(", ");
        try result.writer().print("\"key{}\": {}", .{ i, i });
    }
    try result.append('}');
    
    return result.toOwnedSlice();
}

/// Generates a complex nested structure for comprehensive testing
pub fn generateComplexStructure(allocator: std.mem.Allocator) ![]u8 {
    const template = 
        \\{
        \\  "users": [
        \\    {
        \\      "id": 1,
        \\      "name": "John Doe",
        \\      "active": true,
        \\      "metadata": {
        \\        "last_login": null,
        \\        "permissions": ["read", "write"]
        \\      }
        \\    },
        \\    {
        \\      "id": 2,
        \\      "name": "Jane Smith",
        \\      "active": false,
        \\      "metadata": {
        \\        "last_login": "2023-01-01",
        \\        "permissions": ["read"]
        \\      }
        \\    }
        \\  ],
        \\  "total": 2
        \\}
    ;
    
    return allocator.dupe(u8, template);
}

/// Generates whitespace-heavy JSON for testing whitespace removal
pub fn generateWhitespaceHeavyJson(allocator: std.mem.Allocator) ![]u8 {
    const template = 
        \\{
        \\  "key1": "value1",
        \\  "key2": "value2",
        \\  "key3": "value3"
        \\}
    ;
    
    return allocator.dupe(u8, template);
}

/// Generates JSON with all data types for comprehensive testing
pub fn generateAllTypesJson(allocator: std.mem.Allocator) ![]u8 {
    const template = 
        \\{
        \\  "string": "hello world",
        \\  "number": 123.456,
        \\  "boolean": true,
        \\  "null": null,
        \\  "array": [1, 2, 3, "string", true, null],
        \\  "object": {
        \\    "nested": "value",
        \\    "array": [1, 2, 3],
        \\    "object": {
        \\      "deep": "nested"
        \\    }
        \\  },
        \\  "mixed": [
        \\    "string",
        \\    123,
        \\    true,
        \\    null,
        \\    {
        \\      "key": "value"
        \\    },
        \\    [1, 2, 3]
        \\  ]
        \\}
    ;
    
    return allocator.dupe(u8, template);
}

/// Common test data patterns
pub const TestPatterns = struct {
    pub const empty_structures = [_][]const u8{ "{}", "[]" };
    
    pub const basic_types = [_][]const u8{ 
        "0", "\"\"", "{}", "[]", "true", "false", "null" 
    };
    
    pub const whitespace_only = [_][]const u8{
        " ", "\t", "\n", "\r", "   \t\n\r   "
    };
    
    pub const invalid_literals = [_][]const u8{
        "tru", "truee", "fals", "falsee", "nul", "nulll",
        "True", "False", "Null", "TRUE", "tree", "fulse"
    };
    
    pub const invalid_numbers = [_][]const u8{
        "-", "01", "1.", "1e", "1e+", "1.2.3", "1ee2", "1e2e3", "+1"
    };
    
    pub const invalid_escapes = [_][]const u8{
        "\"\\x\"", "\"\\\"", "\"test", "\"\\u\"", "\"\\u123\"", 
        "\"\\u123g\"", "\"\\uXYZ1\""
    };
    
    pub const chunk_sizes = [_]usize{ 1, 2, 3, 7, 13, 64, 128, 1023 };
};

/// Utilities for generating invalid UTF-8 test data
pub const InvalidUtf8 = struct {
    pub fn generateInvalidByte(allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, &[_]u8{ '"', 0xFF, '"' });
    }
    
    pub fn generateOverlongEncoding(allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, &[_]u8{ '"', 0xC0, 0x80, '"' });
    }
    
    pub fn generateHighSurrogate(allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, &[_]u8{ '"', 0xED, 0xA0, 0x80, '"' });
    }
};