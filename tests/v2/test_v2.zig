const std = @import("std");
const zmin = @import("src/root.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    const input_json =
        \\{
        \\  "name": "John Doe",
        \\  "age": 30,
        \\  "email": "john.doe@example.com"
        \\}
    ;
    
    std.debug.print("Testing v2 minification...\n", .{});
    std.debug.print("Input: {s}\n", .{input_json});
    
    const minified = try zmin.minifyV2(allocator, input_json);
    defer allocator.free(minified);
    
    std.debug.print("Output: {s}\n", .{minified});
    
    std.debug.print("Success! v2 streaming engine is functional.\n", .{});
}