//! Basic usage example for zmin
//!
//! This example demonstrates the simplest way to use zmin for JSON minification.

const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    // Use a general-purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Get command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        try printUsage(args[0]);
        return;
    }
    
    // Example 1: Minify a string
    try example1_string_minification(allocator);
    
    // Example 2: Minify a file
    if (args.len >= 3) {
        try example2_file_minification(allocator, args[1], args[2]);
    }
    
    // Example 3: Validate JSON
    try example3_validation(allocator, args[1]);
}

fn printUsage(program_name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: {s} <input.json> [output.json]\n", .{program_name});
    try stdout.print("\nThis example demonstrates basic zmin usage.\n", .{});
}

fn example1_string_minification(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("\n=== Example 1: String Minification ===\n", .{});
    
    // JSON string with extra whitespace
    const input =
        \\{
        \\    "name": "John Doe",
        \\    "age": 30,
        \\    "city": "New York",
        \\    "hobbies": [
        \\        "reading",
        \\        "coding",
        \\        "hiking"
        \\    ]
        \\}
    ;
    
    // Minify the JSON
    const output = try zmin.minify(allocator, input);
    defer allocator.free(output);
    
    try stdout.print("Original ({d} bytes):\n{s}\n\n", .{ input.len, input });
    try stdout.print("Minified ({d} bytes):\n{s}\n", .{ output.len, output });
    
    const saved = input.len - output.len;
    const percent = @as(f32, @floatFromInt(saved)) / @as(f32, @floatFromInt(input.len)) * 100;
    try stdout.print("\nSaved {d} bytes ({d:.1}%)\n", .{ saved, percent });
}

fn example2_file_minification(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: []const u8,
) !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("\n=== Example 2: File Minification ===\n", .{});
    
    // Read input file
    const input = try std.fs.cwd().readFileAlloc(allocator, input_path, 10 * 1024 * 1024);
    defer allocator.free(input);
    
    try stdout.print("Reading '{s}' ({d} bytes)...\n", .{ input_path, input.len });
    
    // Measure time
    const start = std.time.milliTimestamp();
    
    // Minify
    const output = try zmin.minify(allocator, input);
    defer allocator.free(output);
    
    const duration = std.time.milliTimestamp() - start;
    
    // Write output file
    try std.fs.cwd().writeFile(output_path, output);
    
    try stdout.print("Written '{s}' ({d} bytes)\n", .{ output_path, output.len });
    
    // Print statistics
    const saved = input.len - output.len;
    const percent = @as(f32, @floatFromInt(saved)) / @as(f32, @floatFromInt(input.len)) * 100;
    const throughput = @as(f32, @floatFromInt(input.len)) / @as(f32, @floatFromInt(duration)) * 1000 / (1024 * 1024);
    
    try stdout.print("\nStatistics:\n", .{});
    try stdout.print("  Size reduction: {d} bytes ({d:.1}%)\n", .{ saved, percent });
    try stdout.print("  Processing time: {d} ms\n", .{duration});
    try stdout.print("  Throughput: {d:.1} MB/s\n", .{throughput});
}

fn example3_validation(allocator: std.mem.Allocator, input_path: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("\n=== Example 3: JSON Validation ===\n", .{});
    
    // Test various JSON strings
    const test_cases = [_]struct {
        json: []const u8,
        valid: bool,
        description: []const u8,
    }{
        .{ .json = "{}", .valid = true, .description = "Empty object" },
        .{ .json = "[]", .valid = true, .description = "Empty array" },
        .{ .json = "null", .valid = true, .description = "Null value" },
        .{ .json = "{\"a\":1,}", .valid = false, .description = "Trailing comma" },
        .{ .json = "{invalid}", .valid = false, .description = "Unquoted key" },
        .{ .json = "[1, 2, 3]", .valid = true, .description = "Number array" },
    };
    
    try stdout.print("Testing various JSON strings:\n", .{});
    
    for (test_cases) |test| {
        zmin.validate(test.json) catch |err| {
            if (test.valid) {
                try stdout.print("  ❌ {s}: Unexpected error: {}\n", .{ test.description, err });
            } else {
                try stdout.print("  ✅ {s}: Correctly rejected\n", .{test.description});
            }
            continue;
        };
        
        if (test.valid) {
            try stdout.print("  ✅ {s}: Valid\n", .{test.description});
        } else {
            try stdout.print("  ❌ {s}: Should have been rejected\n", .{test.description});
        }
    }
    
    // Validate the input file
    try stdout.print("\nValidating '{s}'...\n", .{input_path});
    
    const input = try std.fs.cwd().readFileAlloc(allocator, input_path, 10 * 1024 * 1024);
    defer allocator.free(input);
    
    zmin.validate(input) catch |err| {
        try stdout.print("❌ Invalid JSON: {}\n", .{err});
        return;
    };
    
    try stdout.print("✅ Valid JSON file\n", .{});
}