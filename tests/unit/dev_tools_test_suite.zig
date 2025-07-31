const std = @import("std");
const testing = std.testing;
const test_framework = @import("../helpers/test_framework.zig");
const TestRunner = test_framework.TestRunner;
const TestCategory = test_framework.TestCategory;

// Import all dev tools test modules
const dev_tools_tests = @import("dev_tools_tests.zig");
const dev_server_tests = @import("dev_server_tests.zig");
const debugger_tests = @import("debugger_tests.zig");
const plugin_registry_tests = @import("plugin_registry_tests.zig");

/// Comprehensive dev tools test suite configuration
const TestSuiteConfig = struct {
    verbose: bool = false,
    run_performance_tests: bool = true,
    run_error_handling_tests: bool = true,
    run_integration_tests: bool = true,
    max_test_duration_ms: u64 = 30_000, // 30 seconds per test
    memory_limit_mb: u64 = 256, // 256MB memory limit
};

/// Test suite statistics
const TestSuiteStats = struct {
    total_tests: u32 = 0,
    passed_tests: u32 = 0,
    failed_tests: u32 = 0,
    skipped_tests: u32 = 0,
    total_duration_ms: f64 = 0,
    max_memory_used_mb: f64 = 0,

    pub fn getSuccessRate(self: TestSuiteStats) f64 {
        if (self.total_tests == 0) return 0.0;
        return (@as(f64, @floatFromInt(self.passed_tests)) / @as(f64, @floatFromInt(self.total_tests))) * 100.0;
    }

    pub fn format(
        self: TestSuiteStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print(
            \\📊 Test Suite Statistics
            \\{'='<50}
            \\Total Tests:     {d}
            \\✅ Passed:       {d}
            \\❌ Failed:       {d}
            \\⏭️  Skipped:      {d}
            \\🎯 Success Rate: {d:.1}%
            \\⏱️  Duration:     {d:.2}ms
            \\💾 Peak Memory:  {d:.2}MB
            \\
        , .{
            self.total_tests,
            self.passed_tests,
            self.failed_tests,
            self.skipped_tests,
            self.getSuccessRate(),
            self.total_duration_ms,
            self.max_memory_used_mb,
        });
    }
};

/// Main test suite runner
pub const DevToolsTestSuite = struct {
    allocator: std.mem.Allocator,
    config: TestSuiteConfig,
    stats: TestSuiteStats,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: TestSuiteConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .stats = TestSuiteStats{},
        };
    }

    /// Run the complete dev tools test suite
    pub fn runAllTests(self: *Self) !void {
        const suite_start = std.time.nanoTimestamp();

        try self.printHeader();

        // Run all test modules
        try self.runTestModule("Common Error Handling", dev_tools_tests.runAllTests);
        try self.runTestModule("Dev Server", dev_server_tests.runAllTests);
        try self.runTestModule("Debugger", debugger_tests.runAllTests);
        try self.runTestModule("Plugin Registry", plugin_registry_tests.runAllTests);

        // Additional integration tests
        if (self.config.run_integration_tests) {
            try self.runIntegrationTests();
        }

        // Performance tests
        if (self.config.run_performance_tests) {
            try self.runPerformanceTests();
        }

        const suite_end = std.time.nanoTimestamp();
        self.stats.total_duration_ms = @as(f64, @floatFromInt(suite_end - suite_start)) / 1_000_000.0;

        try self.printSummary();
    }

    fn printHeader(self: Self) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.print(
            \\
            \\🔧 Zmin Dev Tools Unit Test Suite
            \\{'='<50}
            \\Configuration:
            \\  Verbose Mode:        {s}
            \\  Performance Tests:   {s}
            \\  Integration Tests:   {s}
            \\  Error Handling:      {s}
            \\  Memory Limit:        {d}MB
            \\  Timeout:             {d}ms
            \\
            \\
        , .{
            if (self.config.verbose) "enabled" else "disabled",
            if (self.config.run_performance_tests) "enabled" else "disabled",
            if (self.config.run_integration_tests) "enabled" else "disabled",
            if (self.config.run_error_handling_tests) "enabled" else "disabled",
            self.config.memory_limit_mb,
            self.config.max_test_duration_ms,
        });
    }

    fn runTestModule(self: *Self, module_name: []const u8, testFn: fn (std.mem.Allocator, bool) anyerror!void) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.print("🧪 Running {s} tests...\n", .{module_name});

        const module_start = std.time.nanoTimestamp();
        var success = true;

        testFn(self.allocator, self.config.verbose) catch |err| {
            try stdout.print("❌ {s} tests failed: {}\n", .{ module_name, err });
            success = false;
            self.stats.failed_tests += 1;
        };

        const module_end = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(module_end - module_start)) / 1_000_000.0;

        if (success) {
            try stdout.print("✅ {s} tests completed in {d:.2}ms\n\n", .{ module_name, duration_ms });
            self.stats.passed_tests += 1;
        } else {
            try stdout.print("❌ {s} tests failed after {d:.2}ms\n\n", .{ module_name, duration_ms });
        }

        self.stats.total_tests += 1;
    }

    fn runIntegrationTests(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("🔗 Running integration tests...\n");

        // Test tool interactions
        try self.testToolInteractions();

        // Test error handling integration
        if (self.config.run_error_handling_tests) {
            try self.testErrorHandlingIntegration();
        }

        try stdout.print("✅ Integration tests completed\n\n");
    }

    fn testToolInteractions(self: *Self) !void {
        // Test that all tools can be initialized without conflicts
        const errors = @import("../../tools/common/errors.zig");

        // Create multiple error reporters
        var reporter1 = errors.ErrorReporter.init(self.allocator, "dev-server");
        var reporter2 = errors.ErrorReporter.init(self.allocator, "debugger");
        var reporter3 = errors.ErrorReporter.init(self.allocator, "plugin-registry");

        // Test that they have correct tool names
        try testing.expectEqualStrings("dev-server", reporter1.tool_name);
        try testing.expectEqualStrings("debugger", reporter2.tool_name);
        try testing.expectEqualStrings("plugin-registry", reporter3.tool_name);

        // Test file operations from different tools
        const file_ops1 = errors.FileOps{ .reporter = &reporter1 };
        const file_ops2 = errors.FileOps{ .reporter = &reporter2 };
        const file_ops3 = errors.FileOps{ .reporter = &reporter3 };

        // All should handle file not found consistently
        const result1 = file_ops1.readFile(self.allocator, "/nonexistent1.txt");
        const result2 = file_ops2.readFile(self.allocator, "/nonexistent2.txt");
        const result3 = file_ops3.readFile(self.allocator, "/nonexistent3.txt");

        try testing.expectError(errors.DevToolError.FileNotFound, result1);
        try testing.expectError(errors.DevToolError.FileNotFound, result2);
        try testing.expectError(errors.DevToolError.FileNotFound, result3);
    }

    fn testErrorHandlingIntegration(self: *Self) !void {
        const errors = @import("../../tools/common/errors.zig");

        // Test error context creation and formatting
        const contexts = [_]errors.ErrorContext{
            errors.context("test-tool", "test-operation"),
            errors.contextWithDetails("test-tool", "test-operation", "test-details"),
            errors.contextWithFile("test-tool", "test-operation", "/test/file.txt"),
        };

        for (contexts) |ctx| {
            var buffer = std.ArrayList(u8).init(self.allocator);
            defer buffer.deinit();

            try ctx.format("", .{}, buffer.writer());

            // All contexts should format without error and contain tool name
            try testing.expect(buffer.items.len > 0);
            try testing.expect(std.mem.indexOf(u8, buffer.items, "test-tool") != null);
        }

        // Test error reporting consistency
        var reporter = errors.ErrorReporter.init(self.allocator, "integration-test");

        const test_errors = [_]errors.DevToolError{
            errors.DevToolError.FileNotFound,
            errors.DevToolError.InvalidArguments,
            errors.DevToolError.PluginLoadFailed,
            errors.DevToolError.InternalError,
        };

        for (test_errors) |err| {
            const ctx = errors.context("integration-test", "error-test");
            // Should not crash
            reporter.report(err, ctx);
        }
    }

    fn runPerformanceTests(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("⚡ Running performance tests...\n");

        // Test error reporting performance
        try self.testErrorReportingPerformance();

        // Test file operations performance
        try self.testFileOperationsPerformance();

        try stdout.print("✅ Performance tests completed\n\n");
    }

    fn testErrorReportingPerformance(self: *Self) !void {
        const errors = @import("../../tools/common/errors.zig");

        var reporter = errors.ErrorReporter.init(self.allocator, "perf-test");
        const ctx = errors.contextWithDetails("perf-test", "performance-test", "testing performance");

        const iterations = 1000;
        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |_| {
            reporter.report(errors.DevToolError.InternalError, ctx);
        }

        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const avg_time_us = (duration_ms * 1000.0) / @as(f64, @floatFromInt(iterations));

        // Error reporting should be fast (< 1ms per report on average)
        try testing.expect(avg_time_us < 1000.0);

        if (self.config.verbose) {
            std.debug.print("Error reporting performance: {d:.2}μs per report\n", .{avg_time_us});
        }
    }

    fn testFileOperationsPerformance(self: *Self) !void {
        const errors = @import("../../tools/common/errors.zig");

        var reporter = errors.ErrorReporter.init(self.allocator, "perf-test");
        const file_ops = errors.FileOps{ .reporter = &reporter };

        const iterations = 100;
        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |i| {
            const filename = try std.fmt.allocPrint(self.allocator, "/tmp/nonexistent_{d}.txt", .{i});
            defer self.allocator.free(filename);

            _ = file_ops.readFile(self.allocator, filename) catch {}; // Ignore errors for perf test
        }

        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const avg_time_ms = duration_ms / @as(f64, @floatFromInt(iterations));

        // File operations should complete quickly (< 10ms per operation on average)
        try testing.expect(avg_time_ms < 10.0);

        if (self.config.verbose) {
            std.debug.print("File operations performance: {d:.2}ms per operation\n", .{avg_time_ms});
        }
    }

    fn printSummary(self: Self) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.print("{}\n", .{self.stats});

        if (self.stats.failed_tests > 0) {
            try stdout.print("❌ Test suite completed with failures\n");
        } else {
            try stdout.print("✅ All tests passed successfully!\n");
        }

        try stdout.print("\n");
    }
};

/// Run the complete dev tools test suite
pub fn runDevToolsTestSuite(allocator: std.mem.Allocator, verbose: bool) !void {
    const config = TestSuiteConfig{
        .verbose = verbose,
        .run_performance_tests = true,
        .run_integration_tests = true,
        .run_error_handling_tests = true,
    };

    var suite = DevToolsTestSuite.init(allocator, config);
    try suite.runAllTests();

    // Exit with error code if tests failed
    if (suite.stats.failed_tests > 0) {
        std.process.exit(1);
    }
}

/// Main entry point for running all dev tools tests
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const verbose = if (args.len > 1)
        std.mem.eql(u8, args[1], "--verbose") or std.mem.eql(u8, args[1], "-v")
    else
        false;

    try runDevToolsTestSuite(allocator, verbose);
}

// Export individual test functions for use by other test runners
test "dev tools common error handling" {
    try dev_tools_tests.runAllTests(testing.allocator, false);
}

test "dev server functionality" {
    try dev_server_tests.runAllTests(testing.allocator, false);
}

test "debugger functionality" {
    try debugger_tests.runAllTests(testing.allocator, false);
}

test "plugin registry functionality" {
    try plugin_registry_tests.runAllTests(testing.allocator, false);
}

test "dev tools integration" {
    var config = TestSuiteConfig{
        .verbose = false,
        .run_performance_tests = false,
        .run_integration_tests = true,
        .run_error_handling_tests = true,
    };

    var suite = DevToolsTestSuite.init(testing.allocator, config);
    try suite.testToolInteractions();
    try suite.testErrorHandlingIntegration();
}
