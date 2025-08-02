//! zmin v2.0 Basic Usage Example
//!
//! This example demonstrates the basic minification capabilities of the zmin v2.0
//! streaming engine using the character-based minifier.
//!
//! Usage: cd to project root, then: zig run examples/v2_basic_example.zig -I src

const std = @import("std");

// For now, inline a simple minifier to make this example self-contained
fn minifyCharBased(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if (input.len == 0) return try allocator.alloc(u8, 0);
    
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    var i: usize = 0;
    var in_string = false;
    
    while (i < input.len) {
        const char = input[i];
        
        if (in_string) {
            try output.append(char);
            if (char == '"' and (i == 0 or input[i - 1] != '\\')) {
                in_string = false;
            } else if (char == '\\' and i + 1 < input.len) {
                i += 1;
                try output.append(input[i]);
            }
        } else {
            switch (char) {
                '"' => {
                    try output.append(char);
                    in_string = true;
                },
                ' ', '\t', '\n', '\r' => {
                    // Skip whitespace outside strings
                },
                else => {
                    try output.append(char);
                },
            }
        }
        
        i += 1;
    }
    
    return output.toOwnedSlice();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== zmin v2.0 Basic Minification Test ===\n", .{});
    
    // Test simple JSON
    {
        const input = "{ \"name\" : \"zmin\" , \"version\" : \"2.0.0\" }";
        std.debug.print("Input:  {s}\n", .{input});
        
        const output = try minifyCharBased(allocator, input);
        defer allocator.free(output);
        
        std.debug.print("Output: {s}\n", .{output});
        std.debug.print("Size reduction: {d} -> {d} bytes ({d:.1}%)\n", .{ 
            input.len, 
            output.len, 
            @as(f64, @floatFromInt(output.len)) / @as(f64, @floatFromInt(input.len)) * 100.0 
        });
    }
    
    std.debug.print("\n", .{});
    
    // Test nested JSON
    {
        const input = 
            \\{
            \\  "project": "zmin",
            \\  "features": [
            \\    "streaming",
            \\    "transformations",
            \\    "high-performance"
            \\  ],
            \\  "stats": {
            \\    "throughput": "10GB/s",
            \\    "latency": "<1ms"
            \\  }
            \\}
        ;
        
        std.debug.print("Nested JSON Input:\n{s}\n", .{input});
        
        const output = try minifyCharBased(allocator, input);
        defer allocator.free(output);
        
        std.debug.print("Minified Output: {s}\n", .{output});
        std.debug.print("Size reduction: {d} -> {d} bytes ({d:.1}%)\n", .{ 
            input.len, 
            output.len, 
            @as(f64, @floatFromInt(output.len)) / @as(f64, @floatFromInt(input.len)) * 100.0 
        });
    }
    
    std.debug.print("\n=== v2.0 Minification Test Complete ===\n", .{});
}