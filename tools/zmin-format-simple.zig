//! zmin-format: Pretty print JSON output
//!
//! Simple JSON formatter using standard library

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    // Simple format: read from stdin, write to stdout
    const input = try std.io.getStdIn().reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(input);
    
    // Parse JSON
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    defer parsed.deinit();
    
    // Write formatted output
    const stdout = std.io.getStdOut().writer();
    try std.json.stringify(parsed.value, .{ .whitespace = .indent_2 }, stdout);
    try stdout.writeByte('\n');
}