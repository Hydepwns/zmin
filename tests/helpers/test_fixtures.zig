//! Common Test Fixtures and Data
//!
//! This module provides reusable test data and fixtures to reduce
//! duplication across test files.

const std = @import("std");

/// Common JSON test cases
pub const JsonTestCases = struct {
    /// Simple object test cases
    pub const simple_objects = [_]TestCase{
        .{ 
            .name = "empty object",
            .input = "{}",
            .expected = "{}"
        },
        .{
            .name = "single property",
            .input = "{\"name\":\"John\"}",
            .expected = "{\"name\":\"John\"}"
        },
        .{
            .name = "multiple properties",
            .input = "{\"name\":\"John\",\"age\":30}",
            .expected = "{\"name\":\"John\",\"age\":30}"
        },
        .{
            .name = "nested object",
            .input = "{\"person\":{\"name\":\"John\",\"age\":30}}",
            .expected = "{\"person\":{\"name\":\"John\",\"age\":30}}"
        },
        .{
            .name = "object with whitespace",
            .input = "{ \"name\" : \"John\" , \"age\" : 30 }",
            .expected = "{\"name\":\"John\",\"age\":30}"
        },
    };
    
    /// Array test cases
    pub const arrays = [_]TestCase{
        .{
            .name = "empty array",
            .input = "[]",
            .expected = "[]"
        },
        .{
            .name = "number array",
            .input = "[1,2,3]",
            .expected = "[1,2,3]"
        },
        .{
            .name = "string array",
            .input = "[\"a\",\"b\",\"c\"]",
            .expected = "[\"a\",\"b\",\"c\"]"
        },
        .{
            .name = "mixed array",
            .input = "[1,\"hello\",true,null]",
            .expected = "[1,\"hello\",true,null]"
        },
        .{
            .name = "nested array",
            .input = "[[1,2],[3,4]]",
            .expected = "[[1,2],[3,4]]"
        },
        .{
            .name = "array with whitespace",
            .input = "[ 1 , 2 , 3 ]",
            .expected = "[1,2,3]"
        },
    };
    
    /// String test cases
    pub const strings = [_]TestCase{
        .{
            .name = "simple string",
            .input = "\"hello\"",
            .expected = "\"hello\""
        },
        .{
            .name = "string with spaces",
            .input = "\"hello world\"",
            .expected = "\"hello world\""
        },
        .{
            .name = "string with escapes",
            .input = "\"hello\\nworld\"",
            .expected = "\"hello\\nworld\""
        },
        .{
            .name = "string with quotes",
            .input = "\"say \\\"hello\\\"\"",
            .expected = "\"say \\\"hello\\\"\""
        },
        .{
            .name = "unicode string",
            .input = "\"\\u0048\\u0065\\u006C\\u006C\\u006F\"",
            .expected = "\"\\u0048\\u0065\\u006C\\u006C\\u006F\""
        },
    };
    
    /// Number test cases
    pub const numbers = [_]TestCase{
        .{
            .name = "integer",
            .input = "42",
            .expected = "42"
        },
        .{
            .name = "negative integer",
            .input = "-42",
            .expected = "-42"
        },
        .{
            .name = "decimal",
            .input = "3.14159",
            .expected = "3.14159"
        },
        .{
            .name = "scientific notation",
            .input = "1.23e+10",
            .expected = "1.23e+10"
        },
        .{
            .name = "negative exponent",
            .input = "1.23e-10",
            .expected = "1.23e-10"
        },
    };
    
    /// Boolean and null test cases
    pub const literals = [_]TestCase{
        .{
            .name = "true",
            .input = "true",
            .expected = "true"
        },
        .{
            .name = "false",
            .input = "false",
            .expected = "false"
        },
        .{
            .name = "null",
            .input = "null",
            .expected = "null"
        },
    };
    
    /// Complex test cases
    pub const complex = [_]TestCase{
        .{
            .name = "mixed complex",
            .input = 
                \\{
                \\  "users": [
                \\    {
                \\      "id": 1,
                \\      "name": "John Doe",
                \\      "email": "john@example.com",
                \\      "active": true
                \\    },
                \\    {
                \\      "id": 2,
                \\      "name": "Jane Smith",
                \\      "email": "jane@example.com",
                \\      "active": false
                \\    }
                \\  ],
                \\  "total": 2,
                \\  "page": 1
                \\}
            ,
            .expected = "{\"users\":[{\"id\":1,\"name\":\"John Doe\",\"email\":\"john@example.com\",\"active\":true},{\"id\":2,\"name\":\"Jane Smith\",\"email\":\"jane@example.com\",\"active\":false}],\"total\":2,\"page\":1}"
        },
    };
};

/// Invalid JSON test cases
pub const InvalidJsonCases = struct {
    pub const syntax_errors = [_][]const u8{
        "{",                    // Unclosed object
        "}",                    // Unexpected closing
        "[",                    // Unclosed array
        "]",                    // Unexpected closing
        "{]",                   // Mismatched brackets
        "[}",                   // Mismatched brackets
        "{\"key\"",            // Missing value
        "{\"key\":}",          // Missing value
        "{\"key\":,}",         // Extra comma
        "[1,]",                // Trailing comma
        "{,}",                 // Leading comma
        "{{}}",                // Double braces
        "{\"a\":1\"b\":2}",    // Missing comma
        "'string'",            // Single quotes
        "{key:\"value\"}",     // Unquoted key
        "{\"key\":undefined}", // Undefined value
    };
    
    pub const invalid_escapes = [_][]const u8{
        "\"\\x41\"",          // Invalid hex escape
        "\"\\u123\"",         // Incomplete unicode
        "\"\\u123g\"",        // Invalid unicode
        "\"\\a\"",            // Invalid escape char
    };
};

/// Performance test data generators
pub const PerformanceData = struct {
    /// Generate a large array of numbers
    pub fn generateNumberArray(allocator: std.mem.Allocator, count: usize) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        errdefer buf.deinit();
        
        try buf.append('[');
        for (0..count) |i| {
            if (i > 0) try buf.append(',');
            try buf.writer().print("{}", .{i});
        }
        try buf.append(']');
        
        return buf.toOwnedSlice();
    }
    
    /// Generate a large object with many properties
    pub fn generateLargeObject(allocator: std.mem.Allocator, prop_count: usize) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        errdefer buf.deinit();
        
        try buf.append('{');
        for (0..prop_count) |i| {
            if (i > 0) try buf.append(',');
            try buf.writer().print("\"prop_{}\":{}", .{i, i});
        }
        try buf.append('}');
        
        return buf.toOwnedSlice();
    }
    
    /// Generate deeply nested JSON
    pub fn generateNestedJson(allocator: std.mem.Allocator, depth: usize) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        errdefer buf.deinit();
        
        // Opening braces
        for (0..depth) |_| {
            try buf.appendSlice("{\"nested\":");
        }
        
        // Center value
        try buf.appendSlice("\"value\"");
        
        // Closing braces
        for (0..depth) |_| {
            try buf.append('}');
        }
        
        return buf.toOwnedSlice();
    }
    
    /// Generate JSON with repeated patterns (good for compression testing)
    pub fn generateRepetitiveJson(allocator: std.mem.Allocator, repeat_count: usize) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        errdefer buf.deinit();
        
        try buf.append('[');
        for (0..repeat_count) |i| {
            if (i > 0) try buf.append(',');
            try buf.appendSlice("{\"id\":123,\"name\":\"John Doe\",\"active\":true}");
        }
        try buf.append(']');
        
        return buf.toOwnedSlice();
    }
};

/// Test case structure
pub const TestCase = struct {
    name: []const u8,
    input: []const u8,
    expected: []const u8,
};

/// Edge case values for testing
pub const EdgeCases = struct {
    /// Maximum safe integer in JavaScript
    pub const max_safe_integer = "9007199254740991";
    
    /// Minimum safe integer in JavaScript
    pub const min_safe_integer = "-9007199254740991";
    
    /// Very small positive number
    pub const tiny_positive = "2.2250738585072014e-308";
    
    /// Very large positive number
    pub const huge_positive = "1.7976931348623157e+308";
    
    /// Unicode test strings
    pub const unicode_samples = [_][]const u8{
        "\"Hello, 世界\"",             // Chinese
        "\"Привет, мир\"",             // Russian
        "\"مرحبا بالعالم\"",           // Arabic
        "\"🌍🌎🌏\"",                  // Emojis
        "\"\\u0000\\u001f\\u007f\"",   // Control characters
    };
};

/// Benchmark configurations
pub const BenchmarkConfigs = struct {
    pub const small_input = BenchmarkConfig{
        .name = "Small JSON",
        .size_category = .small,
        .input_size = 1024,
        .iterations = 10000,
    };
    
    pub const medium_input = BenchmarkConfig{
        .name = "Medium JSON",
        .size_category = .medium,
        .input_size = 64 * 1024,
        .iterations = 1000,
    };
    
    pub const large_input = BenchmarkConfig{
        .name = "Large JSON",
        .size_category = .large,
        .input_size = 1024 * 1024,
        .iterations = 100,
    };
    
    pub const huge_input = BenchmarkConfig{
        .name = "Huge JSON",
        .size_category = .huge,
        .input_size = 10 * 1024 * 1024,
        .iterations = 10,
    };
};

pub const BenchmarkConfig = struct {
    name: []const u8,
    size_category: SizeCategory,
    input_size: usize,
    iterations: usize,
    
    pub const SizeCategory = enum {
        small,
        medium,
        large,
        huge,
    };
};

/// Get all basic test cases
pub fn getAllBasicTests() []const TestCase {
    return JsonTestCases.simple_objects ++ 
           JsonTestCases.arrays ++ 
           JsonTestCases.strings ++ 
           JsonTestCases.numbers ++ 
           JsonTestCases.literals;
}

/// Get all invalid test cases
pub fn getAllInvalidTests() []const []const u8 {
    return InvalidJsonCases.syntax_errors ++ 
           InvalidJsonCases.invalid_escapes;
}