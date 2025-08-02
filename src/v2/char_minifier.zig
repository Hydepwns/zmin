const std = @import("std");
const Allocator = std.mem.Allocator;

/// High-performance character-based JSON minifier for v2
/// This bypasses the complex token system for optimal speed
pub fn minifyCharBased(allocator: Allocator, input: []const u8) ![]u8 {
    if (input.len == 0) return try allocator.alloc(u8, 0);
    
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    // Pre-allocate roughly the same size (most JSONs compress by ~20-40%)
    try output.ensureTotalCapacity(input.len);
    
    var i: usize = 0;
    var in_string = false;
    
    while (i < input.len) {
        const char = input[i];
        
        if (in_string) {
            // Inside a string - preserve everything including whitespace
            try output.append(char);
            
            if (char == '"' and (i == 0 or input[i - 1] != '\\')) {
                // End of string (not escaped)
                in_string = false;
            } else if (char == '\\' and i + 1 < input.len) {
                // Escape sequence - copy the next character too
                i += 1;
                try output.append(input[i]);
            }
        } else {
            // Outside strings
            switch (char) {
                '"' => {
                    // Start of string
                    try output.append(char);
                    in_string = true;
                },
                ' ', '\t', '\n', '\r' => {
                    // Skip whitespace outside strings
                },
                '{', '}', '[', ']', ':', ',', '0'...'9', '-', '.', 't', 'f', 'n' => {
                    // Structural characters, numbers, and literal starts
                    try output.append(char);
                },
                'e', 'E' => {
                    // Could be part of scientific notation
                    try output.append(char);
                },
                '+' => {
                    // Could be part of scientific notation
                    try output.append(char);
                },
                else => {
                    // Unknown character - include it to be safe
                    try output.append(char);
                },
            }
        }
        
        i += 1;
    }
    
    return output.toOwnedSlice();
}

/// More aggressive minification with additional optimizations
pub fn minifyAggressiveCharBased(allocator: Allocator, input: []const u8) ![]u8 {
    if (input.len == 0) return try allocator.alloc(u8, 0);
    
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    try output.ensureTotalCapacity(input.len * 3 / 4); // Assume ~25% compression
    
    var i: usize = 0;
    var in_string = false;
    var prev_char: u8 = 0;
    
    while (i < input.len) {
        const char = input[i];
        
        if (in_string) {
            // Inside string - handle escape sequences properly
            try output.append(char);
            
            if (char == '"' and prev_char != '\\') {
                in_string = false;
            } else if (char == '\\' and i + 1 < input.len) {
                // Handle escape sequence
                i += 1;
                try output.append(input[i]);
            }
        } else {
            // Outside strings - aggressive minification
            switch (char) {
                '"' => {
                    try output.append(char);
                    in_string = true;
                },
                ' ', '\t', '\n', '\r' => {
                    // Skip all whitespace outside strings
                },
                '{', '}', '[', ']', ':', ',' => {
                    // Structural characters - no spaces needed
                    try output.append(char);
                },
                '0'...'9', '-', '.', '+' => {
                    // Numbers and scientific notation (without e/E)
                    try output.append(char);
                },
                'a'...'z' => {
                    // Letters - part of true/false/null literals or scientific notation
                    try output.append(char);
                },
                'A'...'Z' => {
                    // Uppercase letters - scientific notation
                    try output.append(char);
                },
                else => {
                    // Unknown character - include to be safe
                    try output.append(char);
                },
            }
        }
        
        prev_char = char;
        i += 1;
    }
    
    return output.toOwnedSlice();
}

/// Validate that the input is valid JSON (basic check)
pub fn isValidBasicJson(input: []const u8) bool {
    if (input.len == 0) return false;
    
    var brace_count: i32 = 0;
    var bracket_count: i32 = 0;
    var in_string = false;
    var i: usize = 0;
    
    while (i < input.len) {
        const char = input[i];
        
        if (in_string) {
            if (char == '"' and (i == 0 or input[i - 1] != '\\')) {
                in_string = false;
            }
        } else {
            switch (char) {
                '"' => in_string = true,
                '{' => brace_count += 1,
                '}' => {
                    brace_count -= 1;
                    if (brace_count < 0) return false;
                },
                '[' => bracket_count += 1,
                ']' => {
                    bracket_count -= 1;
                    if (bracket_count < 0) return false;
                },
                else => {},
            }
        }
        
        i += 1;
    }
    
    return brace_count == 0 and bracket_count == 0 and !in_string;
}

test "char minifier - basic JSON" {
    const allocator = std.testing.allocator;
    
    const input = "{ \"name\" : \"test\" , \"value\" : 42 }";
    const output = try minifyCharBased(allocator, input);
    defer allocator.free(output);
    
    try std.testing.expectEqualStrings("{\"name\":\"test\",\"value\":42}", output);
}

test "char minifier - nested objects" {
    const allocator = std.testing.allocator;
    
    const input = "{ \"user\" : { \"name\" : \"Alice\" , \"age\" : 30 } }";
    const output = try minifyCharBased(allocator, input);
    defer allocator.free(output);
    
    try std.testing.expectEqualStrings("{\"user\":{\"name\":\"Alice\",\"age\":30}}", output);
}

test "char minifier - strings with spaces" {
    const allocator = std.testing.allocator;
    
    const input = "{ \"message\" : \"Hello World\" , \"value\" : 123 }";
    const output = try minifyCharBased(allocator, input);
    defer allocator.free(output);
    
    try std.testing.expectEqualStrings("{\"message\":\"Hello World\",\"value\":123}", output);
}

test "char minifier - escape sequences" {
    const allocator = std.testing.allocator;
    
    const input = "{ \"escaped\" : \"line\\nbreak\\ttab\\\"quote\" }";
    const output = try minifyCharBased(allocator, input);
    defer allocator.free(output);
    
    try std.testing.expectEqualStrings("{\"escaped\":\"line\\nbreak\\ttab\\\"quote\"}", output);
}

test "char minifier - arrays" {
    const allocator = std.testing.allocator;
    
    const input = "[ 1 , 2 , 3 , \"test\" , true , false , null ]";
    const output = try minifyCharBased(allocator, input);
    defer allocator.free(output);
    
    try std.testing.expectEqualStrings("[1,2,3,\"test\",true,false,null]", output);
}

test "char minifier - scientific notation" {
    const allocator = std.testing.allocator;
    
    const input = "{ \"big\" : 1.23e+10 , \"small\" : 4.56E-5 }";
    const output = try minifyCharBased(allocator, input);
    defer allocator.free(output);
    
    try std.testing.expectEqualStrings("{\"big\":1.23e+10,\"small\":4.56E-5}", output);
}

test "char minifier - aggressive mode" {
    const allocator = std.testing.allocator;
    
    const input = 
        \\{
        \\  "name": "test",
        \\  "values": [
        \\    true,
        \\    false,
        \\    null
        \\  ]
        \\}
    ;
    
    const output = try minifyAggressiveCharBased(allocator, input);
    defer allocator.free(output);
    
    try std.testing.expectEqualStrings("{\"name\":\"test\",\"values\":[true,false,null]}", output);
}

test "JSON validation" {
    try std.testing.expect(isValidBasicJson("{\"test\":123}"));
    try std.testing.expect(isValidBasicJson("[1,2,3]"));
    try std.testing.expect(!isValidBasicJson("{invalid"));
    try std.testing.expect(!isValidBasicJson("[1,2,3"));
    try std.testing.expect(!isValidBasicJson(""));
}