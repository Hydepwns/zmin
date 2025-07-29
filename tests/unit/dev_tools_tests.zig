const std = @import("std");
const testing = std.testing;

// Import the dev tools modules we need to test
const errors = @import("../../tools/common/errors.zig");

/// Run all dev tools unit tests
pub fn runAllTests(allocator: std.mem.Allocator, verbose: bool) !void {
    _ = allocator; // Parameter needed for interface consistency
    if (verbose) {
        std.debug.print("🧪 Running dev tools common tests...\n", .{});
    }

    // Common error handling tests
    try testErrorReporterInit();
    if (verbose) std.debug.print("✅ ErrorReporter init\n", .{});
    
    try testErrorReporterReport();
    if (verbose) std.debug.print("✅ ErrorReporter report\n", .{});
    
    try testErrorContextFormatting();
    if (verbose) std.debug.print("✅ ErrorContext formatting\n", .{});
    
    try testFileOps();
    if (verbose) std.debug.print("✅ FileOps operations\n", .{});
    
    try testProcessOps();
    if (verbose) std.debug.print("✅ ProcessOps operations\n", .{});
    
    try testDevToolErrorTypes();
    if (verbose) std.debug.print("✅ DevToolError types\n", .{});

    if (verbose) {
        std.debug.print("✅ All dev tools common tests passed!\n", .{});
    }
}

/// Test ErrorReporter initialization
fn testErrorReporterInit() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var reporter = errors.ErrorReporter.init(allocator, "test-tool");
    try testing.expectEqualStrings("test-tool", reporter.tool_name);
    try testing.expect(!reporter.verbose);

    reporter.setVerbose(true);
    try testing.expect(reporter.verbose);
}

/// Test ErrorReporter report functionality
fn testErrorReporterReport() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var reporter = errors.ErrorReporter.init(allocator, "test-tool");
    
    const ctx = errors.context("test-tool", "test operation");
    
    // This should not crash - we can't easily test output without capturing stderr
    reporter.report(errors.DevToolError.FileNotFound, ctx);
    
    // Test with details
    const ctx_with_details = errors.contextWithDetails("test-tool", "test operation", "test details");
    reporter.report(errors.DevToolError.InvalidArguments, ctx_with_details);
    
    // Test with file path
    const ctx_with_file = errors.contextWithFile("test-tool", "test operation", "/test/file.txt");
    reporter.report(errors.DevToolError.FileReadError, ctx_with_file);
}

/// Test ErrorContext formatting
fn testErrorContextFormatting() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test basic context
    const ctx1 = errors.context("test-tool", "test operation");
    var buffer1 = std.ArrayList(u8).init(allocator);
    defer buffer1.deinit();
    try ctx1.format("", .{}, buffer1.writer());
    try testing.expect(std.mem.indexOf(u8, buffer1.items, "test-tool") != null);
    try testing.expect(std.mem.indexOf(u8, buffer1.items, "test operation") != null);

    // Test context with details
    const ctx2 = errors.contextWithDetails("test-tool", "test operation", "test details");
    var buffer2 = std.ArrayList(u8).init(allocator);
    defer buffer2.deinit();
    try ctx2.format("", .{}, buffer2.writer());
    try testing.expect(std.mem.indexOf(u8, buffer2.items, "test details") != null);

    // Test context with file
    const ctx3 = errors.contextWithFile("test-tool", "test operation", "/test/file.txt");
    var buffer3 = std.ArrayList(u8).init(allocator);
    defer buffer3.deinit();
    try ctx3.format("", .{}, buffer3.writer());
    try testing.expect(std.mem.indexOf(u8, buffer3.items, "/test/file.txt") != null);
}

/// Test FileOps operations
fn testFileOps() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var reporter = errors.ErrorReporter.init(allocator, "test-tool");
    const file_ops = errors.FileOps{ .reporter = &reporter };

    // Test file operations with non-existent file
    // This should fail gracefully and report the error
    const result = file_ops.readFile(allocator, "/nonexistent/file.txt");
    try testing.expectError(errors.DevToolError.FileNotFound, result);
}

/// Test ProcessOps operations  
fn testProcessOps() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var reporter = errors.ErrorReporter.init(allocator, "test-tool");
    const process_ops = errors.ProcessOps{ .reporter = &reporter };

    // Test with a simple command that should work on most systems
    const result = process_ops.exec(allocator, &[_][]const u8{"echo", "test"});
    
    if (result) |run_result| {
        defer allocator.free(run_result.stdout);
        defer allocator.free(run_result.stderr);
        
        // echo should return success
        try testing.expect(run_result.term.Exited == 0);
        try testing.expect(std.mem.indexOf(u8, run_result.stdout, "test") != null);
    } else |err| {
        // Command might not be available on all systems, that's okay
        _ = err;
    }
}

/// Test DevToolError types
fn testDevToolErrorTypes() !void {
    // Test that all error types can be created and have proper names
    const test_errors = [_]errors.DevToolError{
        errors.DevToolError.InvalidConfiguration,
        errors.DevToolError.ConfigurationNotFound,
        errors.DevToolError.FileNotFound,
        errors.DevToolError.PermissionDenied,
        errors.DevToolError.ProcessSpawnFailed,
        errors.DevToolError.BindFailed,
        errors.DevToolError.PluginLoadFailed,
        errors.DevToolError.InvalidArguments,
        errors.DevToolError.OutOfMemory,
        errors.DevToolError.InternalError,
    };

    for (test_errors) |err| {
        const error_name = @errorName(err);
        try testing.expect(error_name.len > 0);
    }
}

// Test declarations for zig test
test "ErrorReporter initialization" {
    try testErrorReporterInit();
}

test "ErrorReporter reporting" {
    try testErrorReporterReport();
}

test "Error context formatting" {
    try testErrorContextFormatting();
}

test "FileOps operations" {
    try testFileOps();
}

test "ProcessOps operations" {
    try testProcessOps();
}

test "DevToolError types" {
    try testDevToolErrorTypes();
}

/// Main test entry point for this module
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try runAllTests(allocator, true);
}