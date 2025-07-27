//! zmin-validate: Simple JSON validator
//!
//! Validates JSON and reports errors

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const input_file = if (args.len > 1) args[1] else null;

    // Read input
    const input = if (input_file) |file| blk: {
        if (std.mem.eql(u8, file, "-")) {
            break :blk try std.io.getStdIn().reader().readAllAlloc(allocator, 10 * 1024 * 1024);
        } else {
            break :blk try std.fs.cwd().readFileAlloc(allocator, file, 10 * 1024 * 1024);
        }
    } else blk: {
        break :blk try std.io.getStdIn().reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    };
    defer allocator.free(input);

    // Validate JSON
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch |err| {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("❌ Invalid JSON: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer parsed.deinit();

    // Success
    const stdout = std.io.getStdOut().writer();
    try stdout.print("✅ Valid JSON\n", .{});
}
