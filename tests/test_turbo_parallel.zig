const std = @import("std");
const modes = @import("src/modes/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    
    // Test input
    const input =
        \\{
        \\  "name"  :  "test"  ,
        \\  "value" :  123  ,
        \\  "array" : [  1  ,  2  ,  3  ]
        \\}
    ;
    
    const output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);
    
    // Test simple mode
    const MinifierInterface = @import("src/modes/minifier_interface.zig").MinifierInterface;
    
    var input_stream = std.io.fixedBufferStream(input);
    var output_stream = std.io.fixedBufferStream(output);
    
    try stdout.print("Testing TURBO mode with parallel processing...\n", .{});
    
    // This will use the new parallel implementation
    try MinifierInterface.minify(allocator, .turbo, input_stream.reader(), output_stream.writer());
    
    const result = output_stream.getWritten();
    try stdout.print("Input:  {s}\n", .{input});
    try stdout.print("Output: {s}\n", .{result});
    try stdout.print("Size reduction: {d} -> {d} bytes\n", .{ input.len, result.len });
}