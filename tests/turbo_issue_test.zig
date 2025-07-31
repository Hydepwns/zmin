const std = @import("std");
const testing = std.testing;
const modes = @import("modes");
const MinifierInterface = @import("minifier_interface").MinifierInterface;

test "turbo mode edge cases" {
    const allocator = testing.allocator;

    const test_cases = [_]struct { name: []const u8, json: []const u8 }{
        .{ .name = "simple", .json = "{\"test\": \"data\"}" },
        .{ .name = "array", .json = "[1, 2, 3]" },
        .{ .name = "nested", .json = "{\"a\": {\"b\": 123}}" },
        .{ .name = "whitespace", .json = "{ \"test\" : \"data\" , \"num\" : 123 }" },
    };

    for (test_cases) |test_case| {
        // Test eco mode (should work)
        {
            const result = try MinifierInterface.minifyString(allocator, .eco, test_case.json);
            defer allocator.free(result);
            std.debug.print("ECO {s}: {} -> {} bytes\n", .{ test_case.name, test_case.json.len, result.len });
        }
        
        // Test sport mode (should work)
        {
            const result = try MinifierInterface.minifyString(allocator, .sport, test_case.json);
            defer allocator.free(result);
            std.debug.print("SPORT {s}: {} -> {} bytes\n", .{ test_case.name, test_case.json.len, result.len });
        }
        
        // Test turbo mode (might fail)
        {
            const result = MinifierInterface.minifyString(allocator, .turbo, test_case.json) catch |err| {
                std.debug.print("TURBO {s}: ERROR - {}\n", .{ test_case.name, err });
                return err;
            };
            defer allocator.free(result);
            std.debug.print("TURBO {s}: {} -> {} bytes\n", .{ test_case.name, test_case.json.len, result.len });
        }
    }
}

test "turbo mode incremental sizes" {
    const allocator = testing.allocator;
    
    // Test with gradually increasing sizes
    const sizes = [_]usize{ 10, 100, 1000, 10000 };
    
    for (sizes) |size| {
        // Generate simple JSON array
        var json = std.ArrayList(u8).init(allocator);
        defer json.deinit();
        
        try json.append('[');
        for (0..size) |i| {
            if (i > 0) try json.appendSlice(", ");
            try json.writer().print("{}", .{i});
        }
        try json.append(']');
        
        const input = try json.toOwnedSlice();
        defer allocator.free(input);
        
        const result = MinifierInterface.minifyString(allocator, .turbo, input) catch |err| {
            std.debug.print("TURBO failed at size {}: {}\n", .{ size, err });
            return err;
        };
        defer allocator.free(result);
        
        std.debug.print("TURBO size {}: {} -> {} bytes\n", .{ size, input.len, result.len });
    }
}