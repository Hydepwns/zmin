const std = @import("std");

// Import and re-export parser module
pub const parser = @import("src/v2/streaming/parser.zig");

// Import the test
const simd_literal_test = @import("tests/v2/streaming/simd_literal_test.zig");

pub fn main() !void {
    std.debug.print("Running SIMD literal parsing tests...\n", .{});
}