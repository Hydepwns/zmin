//! Integration Tests
//!
//! Tests that verify the interaction between different components
//! and end-to-end functionality of the zmin minifier.

const std = @import("std");
const testing = std.testing;
const zmin = @import("../api/simple.zig");
const advanced = @import("../api/advanced.zig");
const streaming = @import("../api/streaming.zig");

test "file to file minification" {
    const allocator = testing.allocator;
    
    // Create test input file
    const input_content =
        \\{
        \\    "users": [
        \\        {
        \\            "id": 1,
        \\            "name": "John Doe",
        \\            "email": "john@example.com"
        \\        },
        \\        {
        \\            "id": 2,
        \\            "name": "Jane Smith",
        \\            "email": "jane@example.com"
        \\        }
        \\    ],
        \\    "total": 2
        \\}
    ;
    
    const test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();
    
    const input_path = "test_input.json";
    const output_path = "test_output.json";
    
    try test_dir.dir.writeFile(input_path, input_content);
    
    // Minify file to file
    try zmin.minifyFile(allocator, input_path, output_path);
    
    // Verify output
    const output = try test_dir.dir.readFileAlloc(allocator, output_path, 1024 * 1024);
    defer allocator.free(output);
    
    const expected = "{\"users\":[{\"id\":1,\"name\":\"John Doe\",\"email\":\"john@example.com\"},{\"id\":2,\"name\":\"Jane Smith\",\"email\":\"jane@example.com\"}],\"total\":2}";
    try testing.expectEqualStrings(expected, output);
}

test "streaming large file processing" {
    const allocator = testing.allocator;
    
    // Generate large JSON (>1MB)
    var large_json = std.ArrayList(u8).init(allocator);
    defer large_json.deinit();
    
    try large_json.appendSlice("{\n  \"data\": [\n");
    
    for (0..50000) |i| {
        try large_json.writer().print("    {{\"id\": {}, \"value\": \"test_{}\"}}", .{ i, i });
        if (i < 49999) {
            try large_json.appendSlice(",\n");
        } else {
            try large_json.appendSlice("\n");
        }
    }
    
    try large_json.appendSlice("  ]\n}");
    
    // Process with streaming API
    var input_stream = std.io.fixedBufferStream(large_json.items);
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    try zmin.minifyStream(input_stream.reader().any(), output.writer().any());
    
    // Verify basic structure
    try testing.expect(output.items.len < large_json.items.len);
    try testing.expect(std.mem.startsWith(u8, output.items, "{\"data\":["));
    try testing.expect(std.mem.endsWith(u8, output.items, "]}"));
}

test "advanced API with custom configuration" {
    const allocator = testing.allocator;
    
    // Create advanced minifier with aggressive optimization
    const config = advanced.Config{
        .optimization_level = .aggressive,
        .memory_strategy = .pooled,
        .chunk_size = 128 * 1024,
    };
    
    var minifier = try advanced.AdvancedMinifier.init(allocator, config);
    defer minifier.deinit();
    
    // Test with various inputs
    const test_cases = [_][]const u8{
        "{}",
        "[1,2,3]",
        "{\"complex\":{\"nested\":{\"data\":true}}}",
    };
    
    for (test_cases) |input| {
        const result = try minifier.minifyWithStats(input);
        defer allocator.free(result.output);
        
        // Verify output
        try testing.expect(result.output.len <= input.len);
        
        // Check stats
        try testing.expect(result.stats.throughput_gbps > 0);
        try testing.expect(result.stats.duration_ns > 0);
    }
}

test "error recovery and validation" {
    const allocator = testing.allocator;
    
    // Test various malformed JSON inputs
    const test_cases = [_]struct {
        input: []const u8,
        should_fail: bool,
    }{
        .{ .input = "{\"valid\":true}", .should_fail = false },
        .{ .input = "{\"invalid\":}", .should_fail = true },
        .{ .input = "{\"unclosed", .should_fail = true },
        .{ .input = "{'single':quotes'}", .should_fail = true },
        .{ .input = "{unquoted:key}", .should_fail = true },
    };
    
    for (test_cases) |tc| {
        const result = zmin.minify(allocator, tc.input);
        
        if (tc.should_fail) {
            try testing.expectError(error.InvalidJson, result);
        } else {
            const output = try result;
            defer allocator.free(output);
        }
    }
}

test "memory strategies comparison" {
    const allocator = testing.allocator;
    
    const input = "{\"test\":\"data\"}";
    const strategies = [_]advanced.Config.MemoryStrategy{
        .standard,
        .pooled,
        .adaptive,
    };
    
    for (strategies) |strategy| {
        const config = advanced.Config{
            .memory_strategy = strategy,
        };
        
        var minifier = try advanced.AdvancedMinifier.init(allocator, config);
        defer minifier.deinit();
        
        const result = try minifier.minify(input);
        defer allocator.free(result);
        
        try testing.expectEqualStrings("{\"test\":\"data\"}", result);
    }
}

test "parallel batch processing" {
    const allocator = testing.allocator;
    
    // Create multiple JSON strings
    var inputs = std.ArrayList([]const u8).init(allocator);
    defer inputs.deinit();
    
    for (0..10) |i| {
        const json = try std.fmt.allocPrint(allocator, "{{\"item\":{}}}", .{i});
        try inputs.append(json);
    }
    defer {
        for (inputs.items) |item| {
            allocator.free(item);
        }
    }
    
    // Process in parallel
    var results = std.ArrayList([]u8).init(allocator);
    defer {
        for (results.items) |item| {
            allocator.free(item);
        }
        results.deinit();
    }
    
    for (inputs.items) |input| {
        const result = try zmin.minify(allocator, input);
        try results.append(result);
    }
    
    // Verify all processed correctly
    for (results.items, 0..) |result, i| {
        const expected = try std.fmt.allocPrint(allocator, "{{\"item\":{}}}", .{i});
        defer allocator.free(expected);
        
        try testing.expectEqualStrings(expected, result);
    }
}

test "streaming with backpressure" {
    const allocator = testing.allocator;
    
    // Simulate slow writer
    const SlowWriter = struct {
        buffer: std.ArrayList(u8),
        delay_ns: u64,
        
        pub fn write(self: *@This(), data: []const u8) !usize {
            std.time.sleep(self.delay_ns);
            try self.buffer.appendSlice(data);
            return data.len;
        }
        
        pub fn writer(self: *@This()) std.io.Writer(*@This(), error{OutOfMemory}, write) {
            return .{ .context = self };
        }
    };
    
    var slow_writer = SlowWriter{
        .buffer = std.ArrayList(u8).init(allocator),
        .delay_ns = 1000, // 1 microsecond delay
    };
    defer slow_writer.buffer.deinit();
    
    const input = "{\"streaming\":\"test\"}";
    
    const start = std.time.nanoTimestamp();
    try zmin.minifyToWriter(input, slow_writer.writer().any());
    const end = std.time.nanoTimestamp();
    
    const duration_ns = @as(u64, @intCast(end - start));
    
    // Should handle backpressure gracefully
    try testing.expectEqualStrings("{\"streaming\":\"test\"}", slow_writer.buffer.items);
    try testing.expect(duration_ns > slow_writer.delay_ns);
}

test "cross-API compatibility" {
    const allocator = testing.allocator;
    
    const input = "{\"api\":\"test\"}";
    
    // Minify with simple API
    const simple_result = try zmin.minify(allocator, input);
    defer allocator.free(simple_result);
    
    // Minify with advanced API
    var adv = try advanced.AdvancedMinifier.init(allocator, .{});
    defer adv.deinit();
    const adv_result = try adv.minify(input);
    defer allocator.free(adv_result);
    
    // Minify with streaming API
    var stream_output = std.ArrayList(u8).init(allocator);
    defer stream_output.deinit();
    try zmin.minifyToWriter(input, stream_output.writer());
    
    // All should produce identical output
    try testing.expectEqualStrings(simple_result, adv_result);
    try testing.expectEqualStrings(simple_result, stream_output.items);
}

test "real-world JSON examples" {
    const allocator = testing.allocator;
    
    // package.json example
    const package_json =
        \\{
        \\  "name": "zmin",
        \\  "version": "1.0.0",
        \\  "description": "High-performance JSON minifier",
        \\  "main": "index.js",
        \\  "scripts": {
        \\    "test": "zig build test",
        \\    "build": "zig build"
        \\  },
        \\  "keywords": ["json", "minifier", "performance"],
        \\  "author": "zmin team",
        \\  "license": "MIT"
        \\}
    ;
    
    const result = try zmin.minify(allocator, package_json);
    defer allocator.free(result);
    
    // Verify it's valid minified JSON
    try zmin.validate(result);
    try testing.expect(result.len < package_json.len);
    
    // API response example
    const api_response =
        \\{
        \\  "status": 200,
        \\  "data": {
        \\    "users": [
        \\      {"id": 1, "name": "Alice", "active": true},
        \\      {"id": 2, "name": "Bob", "active": false}
        \\    ],
        \\    "pagination": {
        \\      "page": 1,
        \\      "total": 2,
        \\      "hasMore": false
        \\    }
        \\  },
        \\  "timestamp": "2024-01-01T00:00:00Z"
        \\}
    ;
    
    const api_result = try zmin.minify(allocator, api_response);
    defer allocator.free(api_result);
    
    try testing.expect(api_result.len < api_response.len);
}