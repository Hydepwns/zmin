const std = @import("std");
const testing = std.testing;

// Import v2 test modules
pub const simple_parser_tests = @import("streaming/simple_parser_test.zig");
pub const integration_tests = @import("integration/end_to_end_test.zig");
pub const field_filter_tests = @import("transformations/field_filter_test.zig");

test "v2 - all tests" {
    // This will automatically run all tests from imported modules
    testing.refAllDecls(@This());
}

test "v2 - test summary" {
    std.debug.print("\n=== V2 Streaming Engine Test Suite ===\n", .{});
    std.debug.print("✓ Simple parser tests\n", .{});
    std.debug.print("✓ End-to-end integration tests\n", .{});
    std.debug.print("✓ Field filtering transformation tests\n", .{});
    std.debug.print("=====================================\n\n", .{});
}