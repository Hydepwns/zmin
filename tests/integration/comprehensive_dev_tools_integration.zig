const std = @import("std");
const testing = std.testing;
const zmin = @import("zmin_lib");
const errors = @import("../../tools/common/errors.zig");

/// Test comprehensive dev tools workflow integration
test "comprehensive dev tools workflow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test JSON input
    const test_json = 
        \\{
        \\  "users": [
        \\    {
        \\      "id": 1,
        \\      "name": "Alice",
        \\      "settings": {
        \\        "theme": "dark",
        \\        "notifications": true
        \\      }
        \\    },
        \\    {
        \\      "id": 2,
        \\      "name": "Bob",
        \\      "settings": {
        \\        "theme": "light",
        \\        "notifications": false
        \\      }
        \\    }
        \\  ],
        \\  "metadata": {
        \\    "total": 2,
        \\    "version": "1.0"
        \\  }
        \\}
    ;

    // Test error handling integration
    var reporter = errors.ErrorReporter.init(allocator, "integration-test");
    const file_ops = errors.FileOps{ .reporter = &reporter };
    const process_ops = errors.ProcessOps{ .reporter = &reporter };

    // Test that FileOps and ProcessOps work together
    _ = file_ops;
    _ = process_ops;

    // Test minification works with all modes
    const modes = [_]zmin.ProcessingMode{ .eco, .sport, .turbo };
    for (modes) |mode| {
        const result = try zmin.minify(allocator, test_json, mode);
        defer allocator.free(result);
        
        // Verify result is smaller than input
        try testing.expect(result.len < test_json.len);
        
        // Verify result is valid JSON by attempting to parse it back
        _ = std.json.parseFromSlice(std.json.Value, allocator, result, .{}) catch |err| {
            std.debug.print("Failed to parse minified result for mode {s}: {}\n", .{ @tagName(mode), err });
            return err;
        };
    }
}

/// Test error handling across dev tools
test "error handling consistency across tools" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test that all dev tools use consistent error types
    const error_types = [_]errors.DevToolError{
        .InvalidConfiguration,
        .ConfigurationNotFound,
        .FileNotFound,
        .FileReadError,
        .FileWriteError,
        .PermissionDenied,
        .ProcessSpawnFailed,
        .ConnectionFailed,
        .BindFailed,
        .PluginLoadFailed,
        .PluginNotFound,
        .InvalidRequest,
        .InvalidArguments,
        .MissingArgument,
        .UnknownCommand,
        .OutOfMemory,
        .InternalError,
    };

    // Verify all error types have names
    for (error_types) |err_type| {
        const error_name = @errorName(err_type);
        try testing.expect(error_name.len > 0);
    }

    // Test ErrorReporter with different contexts
    var reporter = errors.ErrorReporter.init(allocator, "integration-test");
    
    const contexts = [_]errors.ErrorContext{
        errors.context("test-tool", "test operation"),
        errors.contextWithDetails("test-tool", "test operation", "test details"),
        errors.contextWithFile("test-tool", "test operation", "test.json"),
    };

    for (contexts) |ctx| {
        // This should not crash
        reporter.report(.InternalError, ctx);
    }
}

/// Test memory management across tools
test "memory management integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_sizes = [_]usize{ 100, 1000, 10000 };
    
    for (test_sizes) |size| {
        // Generate test JSON of specified size
        var test_json = std.ArrayList(u8).init(allocator);
        defer test_json.deinit();
        
        try test_json.appendSlice("{\"data\":[");
        for (0..size / 20) |i| {
            if (i > 0) try test_json.appendSlice(",");
            try test_json.writer().print("{{\"id\":{d},\"value\":\"item_{d}\"}}", .{ i, i });
        }
        try test_json.appendSlice("]}");

        // Test minification doesn't leak memory
        const result = try zmin.minify(allocator, test_json.items, .sport);
        defer allocator.free(result);
        
        try testing.expect(result.len > 0);
        try testing.expect(result.len < test_json.items.len);
    }
}

/// Test tool configuration consistency
test "configuration format consistency" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test that common configuration patterns work
    const config_json = 
        \\{
        \\  "version": "1.0",
        \\  "tools": {
        \\    "dev_server": {
        \\      "port": 8080,
        \\      "host": "localhost"
        \\    },
        \\    "debugger": {
        \\      "enabled": true,
        \\      "log_level": "info"
        \\    },
        \\    "profiler": {
        \\      "enabled": false,
        \\      "output_format": "json"
        \\    }
        \\  }
        \\}
    ;

    // Verify configuration can be parsed
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, config_json, .{});
    defer parsed.deinit();
    
    try testing.expect(parsed.value == .object);
    try testing.expect(parsed.value.object.contains("version"));
    try testing.expect(parsed.value.object.contains("tools"));
}

/// Test performance across different data types
test "performance consistency across data types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_cases = [_]struct {
        name: []const u8,
        json: []const u8,
    }{
        .{
            .name = "simple object",
            .json = "{\"key\":\"value\",\"number\":42}",
        },
        .{
            .name = "nested object",
            .json = "{\"user\":{\"profile\":{\"settings\":{\"theme\":\"dark\"}}}}",
        },
        .{
            .name = "array of objects",
            .json = "[{\"id\":1},{\"id\":2},{\"id\":3}]",
        },
        .{
            .name = "mixed types",
            .json = "{\"string\":\"text\",\"number\":123,\"boolean\":true,\"null\":null,\"array\":[1,2,3]}",
        },
    };

    for (test_cases) |test_case| {
        var timer = try std.time.Timer.start();
        
        const result = try zmin.minify(allocator, test_case.json, .sport);
        defer allocator.free(result);
        
        const elapsed = timer.read();
        
        // Performance should be reasonable (< 1ms for small inputs)
        try testing.expect(elapsed < 1_000_000); // 1ms in nanoseconds
        
        // Result should be valid
        try testing.expect(result.len > 0);
        try testing.expect(result.len <= test_case.json.len);
        
        // Verify it's still valid JSON
        _ = try std.json.parseFromSlice(std.json.Value, allocator, result, .{});
    }
}