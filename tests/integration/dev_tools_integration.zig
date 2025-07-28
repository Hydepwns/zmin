const std = @import("std");
const testing = std.testing;

// Import the dev tools
const config_manager = @import("../../tools/config_manager.zig");
const dev_server = @import("../../tools/dev_server.zig");
const debugger = @import("../../tools/debugger.zig");
const plugin_registry = @import("../../tools/plugin_registry.zig");
const profiler = @import("../../tools/profiler.zig");
const hot_reloading = @import("../../tools/hot_reloading.zig");
const errors = @import("../../tools/common/errors.zig");

test "integration - config loading across dev tools" {
    var temp_dir = testing.tmpDir(.{});
    defer temp_dir.cleanup();
    
    // Create a test config file
    const config_content =
        \\{
        \\  "dev_server": {
        \\    "port": 8080,
        \\    "host": "localhost"
        \\  },
        \\  "debugger": {
        \\    "port": 9229,
        \\    "log_level": "info"
        \\  },
        \\  "profiler": {
        \\    "output_dir": "/tmp/zmin-profiles",
        \\    "sample_rate": 1000
        \\  },
        \\  "hot_reloading": {
        \\    "watch_patterns": ["*.zig", "*.json"],
        \\    "debounce_ms": 500
        \\  }
        \\}
    ;
    
    const config_path = try temp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(config_path);
    
    const config_file_path = try std.fs.path.join(testing.allocator, &[_][]const u8{ config_path, "zmin.config.json" });
    defer testing.allocator.free(config_file_path);
    
    // Write config file
    try temp_dir.dir.writeFile("zmin.config.json", config_content);
    
    // Test that config_manager can load the config
    var config_mgr = try config_manager.ConfigManager.init(testing.allocator);
    defer config_mgr.deinit();
    
    try config_mgr.loadFromFile(config_file_path);
    
    // Verify config values are accessible
    const dev_server_port = try config_mgr.getInt("dev_server.port");
    try testing.expectEqual(@as(i64, 8080), dev_server_port);
    
    const debugger_port = try config_mgr.getInt("debugger.port");
    try testing.expectEqual(@as(i64, 9229), debugger_port);
    
    const sample_rate = try config_mgr.getInt("profiler.sample_rate");
    try testing.expectEqual(@as(i64, 1000), sample_rate);
}

test "integration - dev server and debugger coordination" {
    var error_reporter = errors.ErrorReporter.init(testing.allocator, "integration-test");
    
    // Create mock dev server configuration
    const server_config = dev_server.ServerConfig{
        .host = "127.0.0.1",
        .port = 8080,
        .debug_port = 9229,
        .enable_debugging = true,
        .log_requests = true,
    };
    
    // Create mock debugger configuration  
    const debugger_config = debugger.DebuggerConfig{
        .port = 9229,
        .enable_inspector = true,
        .break_on_start = false,
        .log_level = debugger.LogLevel.Info,
    };
    
    // Test that both tools can use compatible configurations
    try testing.expectEqual(server_config.debug_port, debugger_config.port);
    try testing.expect(server_config.enable_debugging);
    try testing.expect(debugger_config.enable_inspector);
    
    // Test error reporting integration
    const ctx = errors.contextWithDetails("integration", "dev-server-debugger", "testing coordination");
    error_reporter.report(errors.DevToolError.InvalidArguments, ctx);
    
    // Should not crash or cause issues
}

test "integration - profiler and hot reloading workflow" {
    var temp_dir = testing.tmpDir(.{});
    defer temp_dir.cleanup();
    
    const temp_path = try temp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(temp_path);
    
    // Create test files to watch
    try temp_dir.dir.writeFile("test.zig", "// Test file content");
    try temp_dir.dir.writeFile("config.json", "{}");
    
    // Test hot reloading file detection
    var watcher = try hot_reloading.FileWatcher.init(testing.allocator);
    defer watcher.deinit();
    
    try watcher.addWatchPath(temp_path);
    
    // Test profiler can handle file change events
    var perf_profiler = try profiler.PerformanceProfiler.init(testing.allocator);
    defer perf_profiler.deinit();
    
    try perf_profiler.startProfiling("hot-reload-test");
    
    // Simulate file change
    try temp_dir.dir.writeFile("test.zig", "// Modified content");
    
    // Give some time for file system event
    std.time.sleep(100_000_000); // 100ms
    
    try perf_profiler.stopProfiling();
    
    // Should complete without errors
}

test "integration - plugin registry and config integration" {
    var temp_dir = testing.tmpDir(.{});
    defer temp_dir.cleanup();
    
    const config_content =
        \\{
        \\  "plugins": {
        \\    "enabled": ["test-plugin-1", "test-plugin-2"],
        \\    "disabled": ["test-plugin-3"],
        \\    "search_paths": ["/usr/local/lib/zmin/plugins", "./plugins"]
        \\  }
        \\}
    ;
    
    try temp_dir.dir.writeFile("plugin-config.json", config_content);
    
    const config_path = try temp_dir.dir.realpathAlloc(testing.allocator, "plugin-config.json");
    defer testing.allocator.free(config_path);
    
    // Load config
    var config_mgr = try config_manager.ConfigManager.init(testing.allocator);
    defer config_mgr.deinit();
    
    try config_mgr.loadFromFile(config_path);
    
    // Initialize plugin registry with config
    var registry = try plugin_registry.PluginRegistry.init(testing.allocator);
    defer registry.deinit();
    
    // Test that registry can read plugin configuration
    const enabled_plugins = try config_mgr.getStringArray("plugins.enabled");
    defer {
        for (enabled_plugins) |plugin| {
            testing.allocator.free(plugin);
        }
        testing.allocator.free(enabled_plugins);
    }
    
    try testing.expectEqual(@as(usize, 2), enabled_plugins.len);
    try testing.expectEqualStrings("test-plugin-1", enabled_plugins[0]);
    try testing.expectEqualStrings("test-plugin-2", enabled_plugins[1]);
    
    const disabled_plugins = try config_mgr.getStringArray("plugins.disabled");
    defer {
        for (disabled_plugins) |plugin| {
            testing.allocator.free(plugin);
        }
        testing.allocator.free(disabled_plugins);
    }
    
    try testing.expectEqual(@as(usize, 1), disabled_plugins.len);
    try testing.expectEqualStrings("test-plugin-3", disabled_plugins[0]);
}

test "integration - consistent error handling across tools" {
    const tool_names = [_][]const u8{
        "config-manager",
        "dev-server", 
        "debugger",
        "profiler",
        "hot-reloading",
        "plugin-registry",
    };
    
    // Test that all tools handle common error scenarios consistently
    for (tool_names) |tool_name| {
        var reporter = errors.ErrorReporter.init(testing.allocator, tool_name);
        
        // Test file not found error
        const file_ctx = errors.contextWithFile(tool_name, "file-operation", "/nonexistent/file.txt");
        reporter.report(errors.DevToolError.FileNotFound, file_ctx);
        
        // Test invalid arguments error
        const args_ctx = errors.contextWithDetails(tool_name, "argument-parsing", "invalid port number");
        reporter.report(errors.DevToolError.InvalidArguments, args_ctx);
        
        // Test internal error
        const internal_ctx = errors.context(tool_name, "internal-operation");
        reporter.report(errors.DevToolError.InternalError, internal_ctx);
        
        // Should all complete without crashing
    }
}

test "integration - cross tool communication" {
    var temp_dir = testing.tmpDir(.{});
    defer temp_dir.cleanup();
    
    // Create shared state directory
    try temp_dir.dir.makeDir("shared");
    
    const shared_path = try temp_dir.dir.realpathAlloc(testing.allocator, "shared");
    defer testing.allocator.free(shared_path);
    
    // Test profiler writing data that dev server can read
    var perf_profiler = try profiler.PerformanceProfiler.init(testing.allocator);
    defer perf_profiler.deinit();
    
    const profile_file = try std.fs.path.join(testing.allocator, &[_][]const u8{ shared_path, "profile.json" });
    defer testing.allocator.free(profile_file);
    
    try perf_profiler.startProfiling("cross-tool-test");
    
    // Simulate some work
    std.time.sleep(10_000_000); // 10ms
    
    try perf_profiler.stopProfiling();
    try perf_profiler.exportProfile(profile_file);
    
    // Test that other tools can read the profile data
    const file_ops = errors.FileOps{ .reporter = &errors.ErrorReporter.init(testing.allocator, "test") };
    const profile_content = try file_ops.readFile(testing.allocator, profile_file);
    defer testing.allocator.free(profile_content);
    
    // Should be valid JSON
    try testing.expect(profile_content.len > 0);
    try testing.expect(std.mem.startsWith(u8, profile_content, "{"));
    try testing.expect(std.mem.endsWith(u8, profile_content, "}"));
}

test "integration - concurrent tool performance" {
    const allocator = testing.allocator;
    
    // Test that multiple tools can run concurrently without conflicts
    var config_mgr = try config_manager.ConfigManager.init(allocator);
    defer config_mgr.deinit();
    
    var registry = try plugin_registry.PluginRegistry.init(allocator);
    defer registry.deinit();
    
    var perf_profiler = try profiler.PerformanceProfiler.init(allocator);
    defer perf_profiler.deinit();
    
    // Start profiling
    try perf_profiler.startProfiling("concurrent-test");
    
    // Simulate concurrent operations
    const operations = 100;
    
    for (0..operations) |i| {
        // Config operations
        try config_mgr.setString("test.key", "test-value");
        _ = config_mgr.getString("test.key") catch null;
        
        // Registry operations (mock)
        const plugin_name = try std.fmt.allocPrint(allocator, "test-plugin-{d}", .{i});
        defer allocator.free(plugin_name);
        
        // Should handle rapid operations
        if (i % 10 == 0) {
            std.time.sleep(1_000_000); // 1ms pause every 10 operations
        }
    }
    
    try perf_profiler.stopProfiling();
    
    // All tools should still be functional
    try testing.expectEqualStrings("test-value", try config_mgr.getString("test.key"));
}

test "integration - tool failure recovery" {
    var temp_dir = testing.tmpDir(.{});
    defer temp_dir.cleanup();
    
    // Create invalid config file
    const invalid_config = "{ invalid json content";
    try temp_dir.dir.writeFile("invalid.json", invalid_config);
    
    const config_path = try temp_dir.dir.realpathAlloc(testing.allocator, "invalid.json");
    defer testing.allocator.free(config_path);
    
    // Test that tools handle invalid config gracefully
    var config_mgr = try config_manager.ConfigManager.init(testing.allocator);
    defer config_mgr.deinit();
    
    const load_result = config_mgr.loadFromFile(config_path);
    try testing.expectError(errors.DevToolError.InvalidConfig, load_result);
    
    // Tool should still be usable after error
    try config_mgr.setString("recovery.test", "success");
    try testing.expectEqualStrings("success", try config_mgr.getString("recovery.test"));
    
    // Test error propagation to other tools
    var reporter = errors.ErrorReporter.init(testing.allocator, "recovery-test");
    const ctx = errors.contextWithFile("recovery-test", "config-load", config_path);
    reporter.report(errors.DevToolError.InvalidConfig, ctx);
    
    // Should not crash the application
}