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

// Export v2 streaming transformation engine
pub const v2 = @import("v2/mod.zig");
pub const ZminEngine = v2.ZminEngine;
pub const StreamingParser = v2.StreamingParser;
pub const TransformationPipeline = v2.TransformationPipeline;

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

// v2 convenience functions
pub fn minifyV2(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return v2.minify(allocator, input);
}

pub fn benchmarkV2(allocator: std.mem.Allocator, input: []const u8, iterations: usize) !v2.BenchmarkResult {
    return v2.benchmark(allocator, input, iterations);
}
