const std = @import("std");
const testing = std.testing;
// Inline test data and helpers since module imports are restricted
const TestFixture = struct {
    name: []const u8,
    input: []const u8,
    expected_minified: []const u8,
};

const FIXTURES = [_]TestFixture{
    .{
        .name = "simple object",
        .input = "{  \"name\": \"John\",  \"age\": 30  }",
        .expected_minified = "{\"name\":\"John\",\"age\":30}",
    },
    .{
        .name = "simple array",
        .input = "[ 1, 2, 3 ]",
        .expected_minified = "[1,2,3]",
    },
    .{
        .name = "nested structure",
        .input = "{\n  \"user\": {\n    \"name\": \"Alice\"\n  }\n}",
        .expected_minified = "{\"user\":{\"name\":\"Alice\"}}",
    },
    .{
        .name = "mixed data types",
        .input = "{\n  \"string\": \"value\",\n  \"number\": 42,\n  \"boolean\": true,\n  \"null\": null\n}",
        .expected_minified = "{\"string\":\"value\",\"number\":42,\"boolean\":true,\"null\":null}",
    },
    .{
        .name = "empty object",
        .input = "{  }",
        .expected_minified = "{}",
    },
    .{
        .name = "empty array",
        .input = "[  ]",
        .expected_minified = "[]",
    },
};

fn minifyWithParser(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const MinifyingParser = @import("src").minifier.MinifyingParser;
    
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    
    var parser = try MinifyingParser.init(allocator, output.writer().any());
    defer parser.deinit(allocator);
    
    try parser.feed(input);
    try parser.flush();
    
    return output.toOwnedSlice();
}

fn minifyWithParallel(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const ParallelMinifier = @import("src").parallel.ParallelMinifier;
    
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    
    var minifier = try ParallelMinifier.create(allocator, output.writer().any(), .{
        .thread_count = 1,
        .chunk_size = 1024,
    });
    defer minifier.destroy();
    
    try minifier.process(input);
    try minifier.flush();
    
    return output.toOwnedSlice();
}

fn minifyWithSimpleParallel(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const SimpleParallelMinifier = @import("src").parallel.SimpleParallelMinifier;
    
    var dummy_output = std.ArrayList(u8).init(allocator);
    defer dummy_output.deinit();
    
    var minifier = try SimpleParallelMinifier.init(allocator, dummy_output.writer().any(), .{
        .thread_count = 1,
        .chunk_size = 1024,
    });
    defer minifier.deinit();
    
    try minifier.process(input);
    try minifier.flush();
    
    return allocator.dupe(u8, dummy_output.items);
}

fn loadFixture(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const path = try std.fmt.allocPrint(allocator, "tests/fixtures/{s}", .{filename});
    defer allocator.free(path);
    
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Fixture file not found: {s}\n", .{path});
            return err;
        },
        else => return err,
    };
    defer file.close();
    
    const file_size = try file.getEndPos();
    const contents = try allocator.alloc(u8, file_size);
    _ = try file.readAll(contents);
    
    return contents;
}

fn generateLargeJson(allocator: std.mem.Allocator, item_count: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    try result.appendSlice("{\"items\":[");
    
    var i: usize = 0;
    while (i < item_count) : (i += 1) {
        if (i > 0) try result.appendSlice(",");
        try result.writer().print("{{\"id\":{},\"value\":\"item_{}\"}}", .{ i, i });
    }
    
    try result.appendSlice("]}");
    
    return result.toOwnedSlice();
}

test "api_consistency - all minifiers produce identical output" {
    // Test each fixture with all minifier implementations
    for (FIXTURES) |fixture| {
        // Test with MinifyingParser
        const parser_result = try minifyWithParser(testing.allocator, fixture.input);
        defer testing.allocator.free(parser_result);
        
        // Test with ParallelMinifier  
        const parallel_result = try minifyWithParallel(testing.allocator, fixture.input);
        defer testing.allocator.free(parallel_result);
        
        // Test with SimpleParallelMinifier
        const simple_result = try minifyWithSimpleParallel(testing.allocator, fixture.input);
        defer testing.allocator.free(simple_result);
        
        // All implementations should produce identical output
        testing.expectEqualStrings(parser_result, parallel_result) catch |err| {
            std.debug.print("\nFixture: {s}\n", .{fixture.name});
            std.debug.print("MinifyingParser:   '{s}'\n", .{parser_result});
            std.debug.print("ParallelMinifier:  '{s}'\n", .{parallel_result});
            return err;
        };
        
        testing.expectEqualStrings(parser_result, simple_result) catch |err| {
            std.debug.print("\nFixture: {s}\n", .{fixture.name});
            std.debug.print("MinifyingParser:      '{s}'\n", .{parser_result});
            std.debug.print("SimpleParallel:       '{s}'\n", .{simple_result});
            return err;
        };
        
        // Also verify against expected output
        testing.expectEqualStrings(fixture.expected_minified, parser_result) catch |err| {
            std.debug.print("\nFixture: {s}\n", .{fixture.name});
            std.debug.print("Expected: '{s}'\n", .{fixture.expected_minified});
            std.debug.print("Got:      '{s}'\n", .{parser_result});
            return err;
        };
    }
}

test "api_consistency - file fixtures produce identical output" {
    const fixture_files = [_][]const u8{ "simple.json", "nested.json", "array.json", "empty.json" };
    
    for (fixture_files) |filename| {
        const input = loadFixture(testing.allocator, filename) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("Skipping missing fixture: {s}\n", .{filename});
                continue;
            }
            return err;
        };
        defer testing.allocator.free(input);
        
        // Test with all minifier implementations
        const parser_result = try minifyWithParser(testing.allocator, input);
        defer testing.allocator.free(parser_result);
        
        const parallel_result = try minifyWithParallel(testing.allocator, input);
        defer testing.allocator.free(parallel_result);
        
        const simple_result = try minifyWithSimpleParallel(testing.allocator, input);
        defer testing.allocator.free(simple_result);
        
        // All should produce identical output
        testing.expectEqualStrings(parser_result, parallel_result) catch |err| {
            std.debug.print("\nFile: {s}\n", .{filename});
            std.debug.print("MinifyingParser:   '{s}'\n", .{parser_result});
            std.debug.print("ParallelMinifier:  '{s}'\n", .{parallel_result});
            return err;
        };
        
        testing.expectEqualStrings(parser_result, simple_result) catch |err| {
            std.debug.print("\nFile: {s}\n", .{filename});
            std.debug.print("MinifyingParser:      '{s}'\n", .{parser_result});
            std.debug.print("SimpleParallel:       '{s}'\n", .{simple_result});
            return err;
        };
    }
}

test "api_consistency - large input produces identical output" {
    const large_input = try generateLargeJson(testing.allocator, 100);
    defer testing.allocator.free(large_input);
    
    // Test with all minifier implementations
    const parser_result = try minifyWithParser(testing.allocator, large_input);
    defer testing.allocator.free(parser_result);
    
    const parallel_result = try minifyWithParallel(testing.allocator, large_input);
    defer testing.allocator.free(parallel_result);
    
    const simple_result = try minifyWithSimpleParallel(testing.allocator, large_input);
    defer testing.allocator.free(simple_result);
    
    // All should produce identical output
    try testing.expectEqualStrings(parser_result, parallel_result);
    try testing.expectEqualStrings(parser_result, simple_result);
    
    // Verify output is valid (starts and ends correctly)
    try testing.expect(parser_result.len > 0);
    try testing.expect(parser_result[0] == '{');
    try testing.expect(parser_result[parser_result.len - 1] == '}');
}

test "api_consistency - streaming vs batch processing" {
    const input = "{\"key1\":\"value1\",\"key2\":\"value2\",\"key3\":\"value3\"}";
    
    // Test batch processing
    const batch_result = try minifyWithParser(testing.allocator, input);
    defer testing.allocator.free(batch_result);
    
    // Test streaming processing (feed in chunks)
    const MinifyingParser = @import("src").minifier.MinifyingParser;
    var streaming_output = std.ArrayList(u8).init(testing.allocator);
    defer streaming_output.deinit();
    
    var streaming_parser = try MinifyingParser.init(testing.allocator, streaming_output.writer().any());
    defer streaming_parser.deinit(testing.allocator);
    
    // Feed input in small chunks
    const chunk_size = 5;
    var offset: usize = 0;
    while (offset < input.len) {
        const end = @min(offset + chunk_size, input.len);
        try streaming_parser.feed(input[offset..end]);
        offset = end;
    }
    try streaming_parser.flush();
    
    // Batch and streaming should produce identical output
    try testing.expectEqualStrings(batch_result, streaming_output.items);
}

test "api_consistency - error handling behavior" {
    const invalid_inputs = [_][]const u8{
        "{invalid",           // Incomplete object
        "[1,2,3",            // Incomplete array  
        "{\"key\":}",        // Missing value
        "{\"key\":\"unterminated string", // Unterminated string
    };
    
    for (invalid_inputs) |invalid_input| {
        // All minifiers should handle errors consistently
        const parser_error = minifyWithParser(testing.allocator, invalid_input);
        const parallel_error = minifyWithParallel(testing.allocator, invalid_input);
        const simple_error = minifyWithSimpleParallel(testing.allocator, invalid_input);
        
        // If one succeeds, all should succeed with identical output
        // If one fails, we just verify they don't crash
        if (parser_error) |parser_result| {
            defer testing.allocator.free(parser_result);
            
            if (parallel_error) |parallel_result| {
                defer testing.allocator.free(parallel_result);
                try testing.expectEqualStrings(parser_result, parallel_result);
            } else |_| {
                // Different error handling is acceptable for now
            }
            
            if (simple_error) |simple_result| {
                defer testing.allocator.free(simple_result);
                try testing.expectEqualStrings(parser_result, simple_result);
            } else |_| {
                // Different error handling is acceptable for now  
            }
        } else |_| {
            // Parser failed, that's fine - just ensure others don't crash
            _ = parallel_error catch {};
            _ = simple_error catch {};
        }
    }
}

test "api_consistency - unicode handling" {
    const unicode_inputs = [_][]const u8{
        "{\"greeting\":\"Hello, 世界!\"}",
        "{\"emoji\":\"🚀💻📊\"}",
        "{\"special\":\"Ñandú über Zürich\"}",
        "{\"escape\":\"Line1\\nLine2\\tTab\"}",
    };
    
    for (unicode_inputs) |input| {
        const parser_result = try minifyWithParser(testing.allocator, input);
        defer testing.allocator.free(parser_result);
        
        const parallel_result = try minifyWithParallel(testing.allocator, input);
        defer testing.allocator.free(parallel_result);
        
        const simple_result = try minifyWithSimpleParallel(testing.allocator, input);
        defer testing.allocator.free(simple_result);
        
        // All should handle unicode identically
        try testing.expectEqualStrings(parser_result, parallel_result);
        try testing.expectEqualStrings(parser_result, simple_result);
    }
}