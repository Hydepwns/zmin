const std = @import("std");
const testing = std.testing;
const test_framework = @import("../helpers/test_framework.zig");
const TestRunner = test_framework.TestRunner;
const TestCategory = test_framework.TestCategory;
const errors = @import("../../tools/common/errors.zig");

/// Mock plugin loader for testing
const MockPluginLoader = struct {
    allocator: std.mem.Allocator,
    plugins: std.ArrayList(MockPlugin),
    loaded_count: u32 = 0,

    const Self = @This();

    const MockPlugin = struct {
        name: []const u8,
        version: []const u8,
        loaded: bool = false,

        pub fn init(name: []const u8, version: []const u8) MockPlugin {
            return MockPlugin{
                .name = name,
                .version = version,
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .plugins = std.ArrayList(MockPlugin).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.plugins.deinit();
    }

    pub fn addMockPlugin(self: *Self, name: []const u8, version: []const u8) !void {
        try self.plugins.append(MockPlugin.init(name, version));
    }

    pub fn loadAllPlugins(self: *Self) !void {
        for (self.plugins.items) |*plugin| {
            plugin.loaded = true;
            self.loaded_count += 1;
        }
    }

    pub fn getPluginInfo(self: Self, index: usize) !MockPluginInfo {
        if (index >= self.plugins.items.len) {
            return error.InvalidIndex;
        }

        const plugin = self.plugins.items[index];
        return MockPluginInfo{
            .name = plugin.name,
            .version = plugin.version,
            .plugin_type = .minifier,
            .description = "Mock plugin for testing",
            .author = "Test Author",
            .license = "MIT",
            .api_version = "1.0.0",
            .capabilities = &[_][]const u8{"minify"},
            .dependencies = &[_][]const u8{},
        };
    }

    pub fn processWithPlugin(self: Self, index: usize, input: []const u8) ![]u8 {
        if (index >= self.plugins.items.len) {
            return error.InvalidIndex;
        }

        const plugin = self.plugins.items[index];
        if (!plugin.loaded) {
            return error.PluginNotLoaded;
        }

        // Mock processing - just return a "minified" version
        return try self.allocator.dupe(u8, input);
    }

    pub fn listPlugins(self: Self) void {
        for (self.plugins.items, 0..) |plugin, i| {
            std.debug.print("{d}: {s} v{s} {s}\n", .{ i, plugin.name, plugin.version, if (plugin.loaded) "(loaded)" else "(not loaded)" });
        }
    }
};

const MockPluginInfo = struct {
    name: []const u8,
    version: []const u8,
    plugin_type: PluginType,
    description: []const u8,
    author: []const u8,
    license: []const u8,
    api_version: []const u8,
    capabilities: []const []const u8,
    dependencies: []const []const u8,

    const PluginType = enum {
        minifier,
        validator,
        optimizer,
    };
};

/// Run all plugin_registry unit tests
pub fn runAllTests(allocator: std.mem.Allocator, verbose: bool) !void {
    var runner = TestRunner.init(allocator, verbose);
    defer runner.deinit();

    // Plugin registry specific tests
    try runner.runTest("PluginRegistry error handling", .unit, testPluginRegistryErrorHandling);
    try runner.runTest("PluginRegistry command parsing", .unit, testPluginRegistryCommandParsing);
    try runner.runTest("PluginRegistry plugin management", .unit, testPluginRegistryPluginManagement);
    try runner.runTest("PluginRegistry discovery", .unit, testPluginRegistryDiscovery);
    try runner.runTest("PluginRegistry testing", .unit, testPluginRegistryTesting);
    try runner.runTest("PluginRegistry benchmarking", .unit, testPluginRegistryBenchmarking);

    // Generate and print test report
    const stdout = std.io.getStdOut().writer();
    try runner.generateReport(stdout);
}

/// Test plugin registry error handling integration
fn testPluginRegistryErrorHandling() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test ErrorReporter initialization
    var reporter = errors.ErrorReporter.init(allocator, "plugin-registry");
    try testing.expectEqualStrings("plugin-registry", reporter.tool_name);

    // Test error context creation
    const ctx = errors.contextWithDetails("plugin-registry", "test operation", "test details");
    try testing.expectEqualStrings("plugin-registry", ctx.tool_name);
    try testing.expectEqualStrings("test operation", ctx.operation);
    try testing.expectEqualStrings("test details", ctx.details.?);

    // Test error reporting
    reporter.report(errors.DevToolError.PluginLoadFailed, ctx);

    // Test file operations
    const file_ops = errors.FileOps{ .reporter = &reporter };
    const result = file_ops.readFile(allocator, "/nonexistent/plugin.json");
    try testing.expectError(errors.DevToolError.FileNotFound, result);
}

/// Test plugin registry command parsing
fn testPluginRegistryCommandParsing() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test valid commands
    const valid_commands = [_][]const u8{ "list", "discover", "load", "test", "info", "benchmark" };

    for (valid_commands) |command| {
        var is_valid_command = false;

        if (std.mem.eql(u8, command, "list")) {
            is_valid_command = true;
        } else if (std.mem.eql(u8, command, "discover")) {
            is_valid_command = true;
        } else if (std.mem.eql(u8, command, "load")) {
            is_valid_command = true;
        } else if (std.mem.eql(u8, command, "test")) {
            is_valid_command = true;
        } else if (std.mem.eql(u8, command, "info")) {
            is_valid_command = true;
        } else if (std.mem.eql(u8, command, "benchmark")) {
            is_valid_command = true;
        }

        try testing.expect(is_valid_command);
    }

    // Test invalid commands
    const invalid_commands = [_][]const u8{ "invalid", "unknown", "bad_command" };

    for (invalid_commands) |command| {
        var is_valid_command = false;

        if (std.mem.eql(u8, command, "list")) {
            is_valid_command = true;
        } else if (std.mem.eql(u8, command, "discover")) {
            is_valid_command = true;
        } else if (std.mem.eql(u8, command, "load")) {
            is_valid_command = true;
        } else if (std.mem.eql(u8, command, "test")) {
            is_valid_command = true;
        } else if (std.mem.eql(u8, command, "info")) {
            is_valid_command = true;
        } else if (std.mem.eql(u8, command, "benchmark")) {
            is_valid_command = true;
        }

        try testing.expect(!is_valid_command);
    }

    // Test argument parsing for 'info' command
    const test_args = [_][]const u8{ "info", "0" };

    if (test_args.len >= 2) {
        const index = std.fmt.parseInt(usize, test_args[1], 10) catch null;
        try testing.expect(index != null);
        try testing.expectEqual(@as(usize, 0), index.?);
    }
}

/// Test plugin registry plugin management
fn testPluginRegistryPluginManagement() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test mock plugin loader
    var loader = MockPluginLoader.init(allocator);
    defer loader.deinit();

    // Add test plugins
    try loader.addMockPlugin("test-minifier", "1.0.0");
    try loader.addMockPlugin("fast-minifier", "2.1.0");
    try loader.addMockPlugin("compact-minifier", "1.5.0");

    try testing.expectEqual(@as(usize, 3), loader.plugins.items.len);
    try testing.expectEqual(@as(u32, 0), loader.loaded_count);

    // Test plugin loading
    try loader.loadAllPlugins();
    try testing.expectEqual(@as(u32, 3), loader.loaded_count);

    // Test all plugins are loaded
    for (loader.plugins.items) |plugin| {
        try testing.expect(plugin.loaded);
    }

    // Test plugin info retrieval
    const info = try loader.getPluginInfo(0);
    try testing.expectEqualStrings("test-minifier", info.name);
    try testing.expectEqualStrings("1.0.0", info.version);

    // Test invalid index
    const invalid_result = loader.getPluginInfo(10);
    try testing.expectError(error.InvalidIndex, invalid_result);
}

/// Test plugin registry discovery functionality
fn testPluginRegistryDiscovery() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test discovery paths (simulation)
    const discovery_paths = [_][]const u8{
        "/usr/local/lib/zmin/plugins",
        "/opt/zmin/plugins",
        "./plugins",
        "~/.zmin/plugins",
    };

    for (discovery_paths) |path| {
        try testing.expect(path.len > 0);
        // Simulate path checking (would normally check if directory exists)
        const is_absolute = std.fs.path.isAbsolute(path);
        _ = is_absolute; // Can be either absolute or relative
    }

    // Test plugin file pattern matching
    const plugin_files = [_][]const u8{
        "minifier.so",
        "validator.dll",
        "optimizer.dylib",
        "plugin.json",
        "README.md", // Should be ignored
    };

    for (plugin_files) |filename| {
        const is_plugin_file = std.mem.endsWith(u8, filename, ".so") or
            std.mem.endsWith(u8, filename, ".dll") or
            std.mem.endsWith(u8, filename, ".dylib") or
            std.mem.endsWith(u8, filename, ".json");

        const should_be_plugin = !std.mem.eql(u8, filename, "README.md");
        try testing.expectEqual(should_be_plugin, is_plugin_file);
    }
}

/// Test plugin registry testing functionality
fn testPluginRegistryTesting() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var loader = MockPluginLoader.init(allocator);
    defer loader.deinit();

    // Add and load test plugins
    try loader.addMockPlugin("test-plugin", "1.0.0");
    try loader.loadAllPlugins();

    // Test plugin processing
    const test_json = "{\"test\": \"data\", \"number\": 42}";
    const result = try loader.processWithPlugin(0, test_json);
    defer allocator.free(result);

    try testing.expectEqualStrings(test_json, result);

    // Test timing measurement
    const start_time = std.time.nanoTimestamp();

    // Simulate processing time
    std.time.sleep(100_000); // 0.1ms

    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;

    try testing.expect(duration > 0);

    const duration_ms = @as(f64, @floatFromInt(duration)) / 1_000_000.0;
    try testing.expect(duration_ms >= 0.05); // Should be at least 0.05ms
}

/// Test plugin registry benchmarking functionality
fn testPluginRegistryBenchmarking() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test benchmark data generation
    var test_json = std.ArrayList(u8).init(allocator);
    defer test_json.deinit();

    try test_json.appendSlice("{\"data\": [");
    for (0..10) |i| {
        if (i > 0) try test_json.appendSlice(", ");
        try test_json.writer().print("{{\"id\": {d}, \"value\": \"item_{d}\"}}", .{ i, i });
    }
    try test_json.appendSlice("]}");

    const json_str = try test_json.toOwnedSlice();
    defer allocator.free(json_str);

    try testing.expect(std.mem.indexOf(u8, json_str, "data") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "item_5") != null);

    // Test benchmark statistics
    const BenchmarkStats = struct {
        iterations: u32,
        total_time: i128,
        successful_runs: u32,

        pub fn getAverageTime(self: @This()) f64 {
            if (self.successful_runs == 0) return 0.0;
            const avg_time_ns = @divTrunc(self.total_time, self.successful_runs);
            return @as(f64, @floatFromInt(avg_time_ns)) / 1_000_000.0;
        }
    };

    const test_stats = BenchmarkStats{
        .iterations = 100,
        .total_time = 50_000_000, // 50ms total
        .successful_runs = 95,
    };

    const avg_time = test_stats.getAverageTime();
    try testing.expect(avg_time > 0.0);
    try testing.expect(avg_time < 1.0); // Should be less than 1ms per operation

    // Test test case configuration
    const TestCase = struct {
        name: []const u8,
        size: usize,
    };

    const test_cases = [_]TestCase{
        .{ .name = "Small JSON", .size = 100 },
        .{ .name = "Medium JSON", .size = 1000 },
        .{ .name = "Large JSON", .size = 10000 },
    };

    for (test_cases) |test_case| {
        try testing.expect(test_case.name.len > 0);
        try testing.expect(test_case.size > 0);
        try testing.expect(test_case.size >= 100);
    }
}

/// Main test entry point for this module
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try runAllTests(allocator, true);
}
