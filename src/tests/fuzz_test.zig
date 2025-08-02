//! Fuzz Testing Suite
//!
//! Tests zmin with random and malformed inputs to ensure robustness
//! and proper error handling in all edge cases.

const std = @import("std");
const testing = std.testing;
const zmin = @import("../api/simple.zig");

/// Fuzz test entry point for AFL++ or libFuzzer
pub export fn zig_fuzz_test(data: [*]u8, size: usize) void {
    fuzzMinify(data[0..size]) catch |err| {
        // Errors are expected for invalid JSON
        _ = err;
    };
}

fn fuzzMinify(input: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Try to minify the input
    const result = zmin.minify(allocator, input) catch |err| switch (err) {
        error.InvalidJson => return, // Expected for malformed input
        error.OutOfMemory => return, // Can happen with very large input
        else => return err,
    };
    defer allocator.free(result);
    
    // If minification succeeded, verify the output
    // 1. Output should be valid JSON
    try zmin.validate(result);
    
    // 2. Output should be smaller or equal in size
    try testing.expect(result.len <= input.len);
    
    // 3. Minifying again should produce the same result
    const result2 = try zmin.minify(allocator, result);
    defer allocator.free(result2);
    try testing.expectEqualStrings(result, result2);
}

test "fuzz: random bytes" {
    var prng = std.rand.DefaultPrng.init(12345);
    const random = prng.random();
    const allocator = testing.allocator;
    
    // Test with various sizes of random data
    const sizes = [_]usize{ 0, 1, 10, 100, 1000, 10000 };
    
    for (sizes) |size| {
        const data = try allocator.alloc(u8, size);
        defer allocator.free(data);
        
        for (0..10) |_| {
            random.bytes(data);
            
            // Most random data should fail as invalid JSON
            const result = zmin.minify(allocator, data);
            if (result) |output| {
                allocator.free(output);
                // If it somehow succeeded, it found valid JSON in random data
                // This is extremely unlikely but not impossible
            } else |err| {
                try testing.expectEqual(error.InvalidJson, err);
            }
        }
    }
}

test "fuzz: mutated valid JSON" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(54321);
    const random = prng.random();
    
    const valid_jsons = [_][]const u8{
        "{}",
        "[]",
        "null",
        "true",
        "false",
        "123",
        "\"string\"",
        "{\"key\":\"value\"}",
        "[1,2,3]",
        "{\"a\":{\"b\":{\"c\":123}}}",
    };
    
    for (valid_jsons) |base_json| {
        // Make mutable copy
        const json_copy = try allocator.dupe(u8, base_json);
        defer allocator.free(json_copy);
        
        // Apply various mutations
        for (0..20) |_| {
            const mutation_type = random.int(u8) % 5;
            
            switch (mutation_type) {
                0 => { // Flip random bit
                    if (json_copy.len > 0) {
                        const pos = random.int(usize) % json_copy.len;
                        json_copy[pos] ^= @as(u8, 1) << @intCast(random.int(u3));
                    }
                },
                1 => { // Change random byte
                    if (json_copy.len > 0) {
                        const pos = random.int(usize) % json_copy.len;
                        json_copy[pos] = random.int(u8);
                    }
                },
                2 => { // Swap two bytes
                    if (json_copy.len > 1) {
                        const pos1 = random.int(usize) % json_copy.len;
                        const pos2 = random.int(usize) % json_copy.len;
                        const tmp = json_copy[pos1];
                        json_copy[pos1] = json_copy[pos2];
                        json_copy[pos2] = tmp;
                    }
                },
                3 => { // Insert byte (by overwriting)
                    if (json_copy.len > 0) {
                        const pos = random.int(usize) % json_copy.len;
                        json_copy[pos] = random.int(u8);
                    }
                },
                4 => { // Delete byte (by shifting)
                    if (json_copy.len > 1) {
                        const pos = random.int(usize) % (json_copy.len - 1);
                        std.mem.copyForwards(u8, json_copy[pos..], json_copy[pos + 1 ..]);
                    }
                },
                else => unreachable,
            }
            
            // Test the mutated JSON
            _ = zmin.minify(allocator, json_copy) catch |err| {
                // Invalid JSON is expected after mutation
                _ = err;
                continue;
            };
        }
    }
}

test "fuzz: edge case inputs" {
    const allocator = testing.allocator;
    
    const edge_cases = [_][]const u8{
        "", // Empty
        " ", // Just whitespace
        "\n\n\n", // Just newlines
        "\t\t\t", // Just tabs
        "\"", // Single quote
        "\\", // Single backslash
        "{", // Unclosed brace
        "}", // Unmatched brace
        "[", // Unclosed bracket
        "]", // Unmatched bracket
        "{{", // Double open
        "}}", // Double close
        "[][]", // Adjacent arrays
        "{}{}", // Adjacent objects
        "null null", // Multiple values
        "true false", // Multiple booleans
        "123 456", // Multiple numbers
        "\"\\", // Unclosed escape
        "\"\\u", // Incomplete unicode
        "\"\\u123", // Incomplete unicode
        "\"\\u123g\"", // Invalid unicode
        "\x00", // Null byte
        "\xFF", // High byte
        "{\x00}", // Null in object
        "[\xFF]", // High byte in array
    };
    
    for (edge_cases) |input| {
        _ = zmin.minify(allocator, input) catch |err| {
            // Most of these should fail
            _ = err;
            continue;
        };
    }
}

test "fuzz: deeply nested structures" {
    const allocator = testing.allocator;
    
    // Test various nesting depths
    for (1..100) |depth| {
        // Nested objects
        var obj = std.ArrayList(u8).init(allocator);
        defer obj.deinit();
        
        for (0..depth) |_| {
            try obj.append('{');
        }
        try obj.appendSlice("\"x\":1");
        for (0..depth) |_| {
            try obj.append('}');
        }
        
        _ = zmin.minify(allocator, obj.items) catch |err| {
            // May fail if nesting is too deep
            _ = err;
        };
        
        // Nested arrays
        var arr = std.ArrayList(u8).init(allocator);
        defer arr.deinit();
        
        for (0..depth) |_| {
            try arr.append('[');
        }
        try arr.append('1');
        for (0..depth) |_| {
            try arr.append(']');
        }
        
        _ = zmin.minify(allocator, arr.items) catch |err| {
            // May fail if nesting is too deep
            _ = err;
        };
    }
}

test "fuzz: large repetitive patterns" {
    const allocator = testing.allocator;
    
    // Test with large repetitive structures
    var json = std.ArrayList(u8).init(allocator);
    defer json.deinit();
    
    // Large array of numbers
    try json.append('[');
    for (0..10000) |i| {
        if (i > 0) try json.append(',');
        try json.writer().print("{}", .{i});
    }
    try json.append(']');
    
    const result = try zmin.minify(allocator, json.items);
    defer allocator.free(result);
    
    // Large object with many keys
    json.clearRetainingCapacity();
    try json.append('{');
    for (0..1000) |i| {
        if (i > 0) try json.append(',');
        try json.writer().print("\"key{}\":{}", .{ i, i });
    }
    try json.append('}');
    
    const result2 = try zmin.minify(allocator, json.items);
    allocator.free(result2);
}

test "fuzz: unicode edge cases" {
    const allocator = testing.allocator;
    
    const unicode_tests = [_][]const u8{
        "\"\\u0000\"", // Null character
        "\"\\uFFFF\"", // Max BMP
        "\"\\uD800\"", // High surrogate alone (invalid)
        "\"\\uDC00\"", // Low surrogate alone (invalid)
        "\"\\uD800\\uDC00\"", // Valid surrogate pair
        "\"\xF0\x9F\x98\x80\"", // Emoji
        "\"\xED\xA0\x80\"", // Invalid UTF-8 (surrogate)
        "\"\xF5\x80\x80\x80\"", // Invalid UTF-8 (too high)
        "\"\xC0\x80\"", // Overlong encoding
        "\"\xE0\x80\x80\"", // Overlong encoding
    };
    
    for (unicode_tests) |input| {
        _ = zmin.minify(allocator, input) catch |err| {
            // Some of these are invalid
            _ = err;
            continue;
        };
    }
}

test "fuzz: mixed valid and invalid" {
    const allocator = testing.allocator;
    
    // Test partially valid JSON
    const mixed_cases = [_][]const u8{
        "{\"valid\":true, invalid}",
        "[1,2,3,]", // Trailing comma
        "{\"key\":,}", // Missing value
        "{,\"key\":\"value\"}", // Leading comma
        "{'single':'quotes'}", // Single quotes
        "{unquoted:key}", // Unquoted key
        "{\"key\":undefined}", // Undefined value
        "{\"key\":NaN}", // NaN value
        "{\"key\":Infinity}", // Infinity value
        "{\"key\":.123}", // Leading decimal
        "{\"key\":123.}", // Trailing decimal
        "{\"key\":0x123}", // Hex number
        "{\"key\":0123}", // Octal number
        "{\"key\":+123}", // Explicit plus
    };
    
    for (mixed_cases) |input| {
        const result = zmin.minify(allocator, input);
        try testing.expectError(error.InvalidJson, result);
    }
}

/// Generate random valid JSON for testing
fn generateRandomJSON(allocator: std.mem.Allocator, random: std.rand.Random, max_depth: u32) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);
    errdefer json.deinit();
    
    try generateRandomValue(&json, random, max_depth);
    
    return json.toOwnedSlice();
}

fn generateRandomValue(json: *std.ArrayList(u8), random: std.rand.Random, depth: u32) !void {
    if (depth == 0) {
        // Generate leaf value
        const leaf_type = random.int(u8) % 5;
        switch (leaf_type) {
            0 => try json.appendSlice("null"),
            1 => try json.appendSlice("true"),
            2 => try json.appendSlice("false"),
            3 => try json.writer().print("{}", .{random.int(i32)}),
            4 => {
                try json.append('"');
                const len = random.int(u8) % 20;
                for (0..len) |_| {
                    const c = random.int(u8);
                    if (c >= 32 and c < 127 and c != '"' and c != '\\') {
                        try json.append(c);
                    } else {
                        try json.append('x');
                    }
                }
                try json.append('"');
            },
            else => unreachable,
        }
        return;
    }
    
    const value_type = random.int(u8) % 7;
    switch (value_type) {
        0, 1, 2, 3, 4 => try generateRandomValue(json, random, 0), // Leaf value
        5 => { // Object
            try json.append('{');
            const num_keys = random.int(u8) % 5;
            for (0..num_keys) |i| {
                if (i > 0) try json.append(',');
                try json.writer().print("\"key{}\":", .{i});
                try generateRandomValue(json, random, depth - 1);
            }
            try json.append('}');
        },
        6 => { // Array
            try json.append('[');
            const num_elements = random.int(u8) % 5;
            for (0..num_elements) |i| {
                if (i > 0) try json.append(',');
                try generateRandomValue(json, random, depth - 1);
            }
            try json.append(']');
        },
        else => unreachable,
    }
}