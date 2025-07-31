//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

// Export the minifier module
pub const minifier = @import("minifier");

// Export other modules
pub const parallel = @import("parallel");
pub const parallel_minifier = parallel.ParallelMinifier;
pub const parallel_minifier_simple = parallel.SimpleParallelMinifier;

// Export modes
pub const modes = @import("modes");
pub const ProcessingMode = modes.ProcessingMode;

// Export minifier interface
pub const MinifierInterface = @import("minifier_interface").MinifierInterface;

// Convenience functions
pub fn minify(allocator: std.mem.Allocator, input: []const u8, mode: ProcessingMode) ![]u8 {
    return MinifierInterface.minifyString(allocator, mode, input);
}

pub fn minifyWithMode(allocator: std.mem.Allocator, input: []const u8, mode: ProcessingMode) ![]u8 {
    return MinifierInterface.minifyString(allocator, mode, input);
}

pub fn validate(input: []const u8) !void {
    // Simple validation - just try to parse as JSON
    const null_writer = std.io.null_writer.any();
    var parser = try minifier.MinifyingParser.init(std.heap.page_allocator, null_writer);
    defer parser.deinit(std.heap.page_allocator);

    try parser.feed(input);
    try parser.flush();
}
