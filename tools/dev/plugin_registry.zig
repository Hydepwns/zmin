const std = @import("std");
const plugin_loader = @import("plugin_loader");
const PluginLoader = plugin_loader.PluginLoader;
const PluginDiscovery = plugin_loader.PluginDiscovery;
const errors = @import("common/errors.zig");
const DevToolError = errors.DevToolError;
const ErrorReporter = errors.ErrorReporter;

/// Plugin registry management tool
const PluginRegistry = struct {
    allocator: std.mem.Allocator,
    loader: PluginLoader,
    reporter: ErrorReporter,
    file_ops: errors.FileOps,
    process_ops: errors.ProcessOps,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        var reporter = ErrorReporter.init(allocator, "plugin-registry");
        const file_ops = errors.FileOps{ .reporter = &reporter };
        const process_ops = errors.ProcessOps{ .reporter = &reporter };

        return Self{
            .allocator = allocator,
            .loader = PluginLoader.init(allocator),
            .reporter = reporter,
            .file_ops = file_ops,
            .process_ops = process_ops,
        };
    }

    pub fn deinit(self: *Self) void {
        self.loader.deinit();
    }

    pub fn run(self: *Self, args: []const []const u8) !void {
        if (args.len == 0) {
            try self.showHelp();
            return;
        }

        const command = args[0];

        if (std.mem.eql(u8, command, "list")) {
            try self.listPlugins();
        } else if (std.mem.eql(u8, command, "discover")) {
            try self.discoverPlugins();
        } else if (std.mem.eql(u8, command, "load")) {
            try self.loadPlugins();
        } else if (std.mem.eql(u8, command, "test")) {
            try self.testPlugins();
        } else if (std.mem.eql(u8, command, "info")) {
            if (args.len < 2) {
                self.reporter.report(DevToolError.MissingArgument, errors.contextWithDetails("plugin-registry", "processing info command", "missing plugin index argument"));
                return DevToolError.MissingArgument;
            }
            const index = std.fmt.parseInt(usize, args[1], 10) catch {
                self.reporter.report(DevToolError.InvalidArguments, errors.contextWithDetails("plugin-registry", "parsing plugin index", args[1]));
                return DevToolError.InvalidArguments;
            };
            try self.showPluginInfo(index);
        } else if (std.mem.eql(u8, command, "benchmark")) {
            try self.benchmarkPlugins();
        } else {
            self.reporter.report(DevToolError.UnknownCommand, errors.contextWithDetails("plugin-registry", "processing command", command));
            try self.showHelp();
            return DevToolError.UnknownCommand;
        }
    }

    fn showHelp(self: *Self) !void {
        _ = self;

        std.log.info("Plugin Registry Management Tool", .{});
        std.log.info("==============================", .{});
        std.log.info("", .{});
        std.log.info("Commands:", .{});
        std.log.info("  list      - List all registered plugins", .{});
        std.log.info("  discover  - Discover plugins in standard locations", .{});
        std.log.info("  load      - Load all discovered plugins", .{});
        std.log.info("  test      - Test all loaded plugins", .{});
        std.log.info("  info <N>  - Show detailed info for plugin N", .{});
        std.log.info("  benchmark - Benchmark plugin performance", .{});
        std.log.info("", .{});
        std.log.info("Examples:", .{});
        std.log.info("  plugin-registry discover", .{});
        std.log.info("  plugin-registry list", .{});
        std.log.info("  plugin-registry load", .{});
        std.log.info("  plugin-registry info 0", .{});
        std.log.info("  plugin-registry test", .{});
    }

    fn listPlugins(self: *Self) !void {
        PluginDiscovery.autoDiscover(&self.loader) catch |err| {
            self.reporter.report(err, errors.context("plugin-registry", "discovering plugins for listing"));
            return DevToolError.PluginLoadFailed;
        };
        self.loader.listPlugins();
    }

    fn discoverPlugins(self: *Self) !void {
        std.log.info("🔍 Discovering plugins...", .{});

        PluginDiscovery.autoDiscover(&self.loader) catch |err| {
            self.reporter.report(err, errors.context("plugin-registry", "auto-discovering plugins"));
            return DevToolError.PluginLoadFailed;
        };

        std.log.info("✅ Plugin discovery completed", .{});
        std.log.info("Found {d} plugins", .{self.loader.plugins.items.len});

        if (self.loader.plugins.items.len > 0) {
            std.log.info("", .{});
            self.loader.listPlugins();
        }
    }

    fn loadPlugins(self: *Self) !void {
        PluginDiscovery.autoDiscover(&self.loader) catch |err| {
            self.reporter.report(err, errors.context("plugin-registry", "discovering plugins for loading"));
            return DevToolError.PluginLoadFailed;
        };

        std.log.info("🚀 Loading all plugins...", .{});

        self.loader.loadAllPlugins() catch |err| {
            self.reporter.report(err, errors.context("plugin-registry", "loading all plugins"));
            return DevToolError.PluginLoadFailed;
        };

        std.log.info("✅ Plugin loading completed", .{});
        std.log.info("Loaded {d} out of {d} plugins", .{ self.loader.loaded_count, self.loader.plugins.items.len });

        if (self.loader.loaded_count > 0) {
            std.log.info("", .{});
            self.loader.listPlugins();
        }
    }

    fn testPlugins(self: *Self) !void {
        PluginDiscovery.autoDiscover(&self.loader) catch |err| {
            self.reporter.report(err, errors.context("plugin-registry", "discovering plugins for testing"));
            return DevToolError.PluginLoadFailed;
        };
        self.loader.loadAllPlugins() catch |err| {
            self.reporter.report(err, errors.context("plugin-registry", "loading plugins for testing"));
            return DevToolError.PluginLoadFailed;
        };

        std.log.info("🧪 Testing all loaded plugins...", .{});
        std.log.info("", .{});

        const test_json = "{\"test\": \"data\", \"number\": 42, \"array\": [1, 2, 3]}";

        for (self.loader.plugins.items, 0..) |plugin, i| {
            if (!plugin.loaded) continue;

            const info = self.loader.getPluginInfo(i) catch |err| {
                self.reporter.report(err, errors.contextWithDetails("plugin-registry", "getting plugin info for testing", "plugin index out of range"));
                continue;
            };
            std.log.info("Testing plugin: {s}", .{info.name});

            const start_time = std.time.nanoTimestamp();
            const result = self.loader.processWithPlugin(i, test_json) catch |err| {
                self.reporter.report(err, errors.contextWithDetails("plugin-registry", "testing plugin", info.name));
                std.log.err("  ❌ Test failed: {any}", .{err});
                continue;
            };
            const end_time = std.time.nanoTimestamp();

            const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

            std.log.info("  ✅ Test passed in {d:.2}ms", .{duration_ms});
            std.log.info("  📄 Result length: {d} bytes", .{result.len});

            // Show first 100 characters of result
            const preview_len = @min(result.len, 100);
            std.log.info("  📝 Preview: {s}{s}", .{ result[0..preview_len], if (result.len > 100) "..." else "" });
            std.log.info("", .{});

            self.allocator.free(result);
        }

        std.log.info("✅ Plugin testing completed", .{});
    }

    fn showPluginInfo(self: *Self, index: usize) !void {
        PluginDiscovery.autoDiscover(&self.loader) catch |err| {
            self.reporter.report(err, errors.context("plugin-registry", "discovering plugins for info display"));
            return DevToolError.PluginLoadFailed;
        };
        self.loader.loadAllPlugins() catch |err| {
            self.reporter.report(err, errors.context("plugin-registry", "loading plugins for info display"));
            return DevToolError.PluginLoadFailed;
        };

        const info = self.loader.getPluginInfo(index) catch |err| {
            self.reporter.report(err, errors.contextWithDetails("plugin-registry", "getting plugin info", "invalid plugin index"));
            return DevToolError.PluginNotFound;
        };

        std.log.info("=== Plugin Information ===", .{});
        std.log.info("Name: {s}", .{info.name});
        std.log.info("Version: {s}", .{info.version});
        std.log.info("Type: {s}", .{@tagName(info.plugin_type)});
        std.log.info("Description: {s}", .{info.description});
        std.log.info("Author: {s}", .{info.author});
        std.log.info("License: {s}", .{info.license});
        std.log.info("API Version: {s}", .{info.api_version});
        std.log.info("", .{});
        std.log.info("Capabilities:", .{});
        for (info.capabilities) |capability| {
            std.log.info("  - {s}", .{capability});
        }
        std.log.info("", .{});
        std.log.info("Dependencies:", .{});
        if (info.dependencies.len == 0) {
            std.log.info("  (none)", .{});
        } else {
            for (info.dependencies) |dependency| {
                std.log.info("  - {s}", .{dependency});
            }
        }
    }

    fn benchmarkPlugins(self: *Self) !void {
        PluginDiscovery.autoDiscover(&self.loader) catch |err| {
            self.reporter.report(err, errors.context("plugin-registry", "discovering plugins for benchmarking"));
            return DevToolError.PluginLoadFailed;
        };
        self.loader.loadAllPlugins() catch |err| {
            self.reporter.report(err, errors.context("plugin-registry", "loading plugins for benchmarking"));
            return DevToolError.PluginLoadFailed;
        };

        std.log.info("⚡ Benchmarking plugin performance...", .{});
        std.log.info("", .{});

        // Test with different JSON sizes
        const test_cases = [_]struct {
            name: []const u8,
            size: usize,
        }{
            .{ .name = "Small JSON", .size = 100 },
            .{ .name = "Medium JSON", .size = 1000 },
            .{ .name = "Large JSON", .size = 10000 },
        };

        for (test_cases) |test_case| {
            std.log.info("📊 {s} ({d} bytes)", .{ test_case.name, test_case.size });

            // Generate test JSON
            var test_json = std.ArrayList(u8).init(self.allocator);
            defer test_json.deinit();

            test_json.appendSlice("{\"data\": [") catch |err| {
                self.reporter.report(err, errors.context("plugin-registry", "generating test JSON"));
                return DevToolError.OutOfMemory;
            };
            for (0..test_case.size / 20) |i| {
                if (i > 0) test_json.appendSlice(", ") catch |err| {
                    self.reporter.report(err, errors.context("plugin-registry", "generating test JSON"));
                    return DevToolError.OutOfMemory;
                };
                test_json.writer().print("{{\"id\": {d}, \"value\": \"item_{d}\"}}", .{ i, i }) catch |err| {
                    self.reporter.report(err, errors.context("plugin-registry", "generating test JSON"));
                    return DevToolError.OutOfMemory;
                };
            }
            test_json.appendSlice("]}") catch |err| {
                self.reporter.report(err, errors.context("plugin-registry", "generating test JSON"));
                return DevToolError.OutOfMemory;
            };

            const json_str = test_json.toOwnedSlice() catch |err| {
                self.reporter.report(err, errors.context("plugin-registry", "finalizing test JSON"));
                return DevToolError.OutOfMemory;
            };
            defer self.allocator.free(json_str);

            // Benchmark each plugin
            for (self.loader.plugins.items, 0..) |plugin, i| {
                if (!plugin.loaded) continue;

                const info = self.loader.getPluginInfo(i) catch |err| {
                    self.reporter.report(err, errors.contextWithDetails("plugin-registry", "getting plugin info for benchmarking", "invalid plugin index"));
                    continue;
                };

                // Run multiple iterations for better accuracy
                const iterations = 100;
                var total_time: i128 = 0;
                var successful_runs: u32 = 0;

                for (0..iterations) |_| {
                    const start_time = std.time.nanoTimestamp();

                    if (self.loader.processWithPlugin(i, json_str)) |result| {
                        const end_time = std.time.nanoTimestamp();
                        total_time += end_time - start_time;
                        successful_runs += 1;
                        self.allocator.free(result);
                    } else |_| {
                        // Ignore errors for benchmarking
                    }
                }

                if (successful_runs > 0) {
                    const avg_time_ns = @divTrunc(total_time, successful_runs);
                    const avg_time_ms = @as(f64, @floatFromInt(avg_time_ns)) / 1_000_000.0;

                    std.log.info("  {s}: {d:.3}ms avg ({d} successful runs)", .{ info.name, avg_time_ms, successful_runs });
                } else {
                    std.log.info("  {s}: Failed all runs", .{info.name});
                }
            }

            std.log.info("", .{});
        }

        std.log.info("✅ Benchmarking completed", .{});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Skip program name
    const command_args = if (args.len > 1) args[1..] else args[0..0];

    var registry = PluginRegistry.init(allocator);
    defer registry.deinit();

    try registry.run(command_args);
}
