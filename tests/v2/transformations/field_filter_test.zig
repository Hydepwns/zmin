const std = @import("std");
const testing = std.testing;
const StreamingParser = @import("../../../src/v2/streaming/parser.zig").StreamingParser;
const TransformationPipeline = @import("../../../src/v2/transformations/pipeline.zig").TransformationPipeline;
const OutputStream = @import("../../../src/v2/transformations/pipeline.zig").OutputStream;
const Transformation = @import("../../../src/v2/transformations/pipeline.zig").Transformation;
const TransformationConfig = @import("../../../src/v2/transformations/pipeline.zig").TransformationConfig;
const FilterConfig = @import("../../../src/v2/transformations/pipeline.zig").FilterConfig;

test "Field filtering - include specific fields" {
    const allocator = testing.allocator;
    
    const json = 
        \\{
        \\  "name": "John Doe",
        \\  "age": 30,
        \\  "email": "john@example.com",
        \\  "address": {
        \\    "street": "123 Main St",
        \\    "city": "New York",
        \\    "country": "USA"
        \\  },
        \\  "phone": "+1-555-1234"
        \\}
    ;
    
    // Parse the JSON
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    var token_stream = try parser.parseStreaming(json);
    defer token_stream.deinit();
    
    // Create pipeline with field filter
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    const include_fields = [_][]const u8{ "name", "email" };
    try pipeline.addTransformation(Transformation.init(.{
        .filter_fields = FilterConfig{
            .include = &include_fields,
        },
    }));
    
    // Execute transformation
    var output = OutputStream.init(allocator);
    defer output.deinit();
    
    try pipeline.executeStreaming(token_stream, &output);
    
    const result = output.getBuffer();
    
    // Verify the output contains only name and email
    try testing.expect(std.mem.indexOf(u8, result, "\"name\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"email\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"age\"") == null);
    try testing.expect(std.mem.indexOf(u8, result, "\"address\"") == null);
    try testing.expect(std.mem.indexOf(u8, result, "\"phone\"") == null);
}

test "Field filtering - exclude specific fields" {
    const allocator = testing.allocator;
    
    const json = 
        \\{
        \\  "id": 123,
        \\  "username": "johndoe",
        \\  "password": "secret123",
        \\  "email": "john@example.com",
        \\  "api_key": "abc-123-def"
        \\}
    ;
    
    // Parse the JSON
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    var token_stream = try parser.parseStreaming(json);
    defer token_stream.deinit();
    
    // Create pipeline with field filter
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    const exclude_fields = [_][]const u8{ "password", "api_key" };
    try pipeline.addTransformation(Transformation.init(.{
        .filter_fields = FilterConfig{
            .exclude = &exclude_fields,
        },
    }));
    
    // Execute transformation
    var output = OutputStream.init(allocator);
    defer output.deinit();
    
    try pipeline.executeStreaming(token_stream, &output);
    
    const result = output.getBuffer();
    
    // Verify sensitive fields are excluded
    try testing.expect(std.mem.indexOf(u8, result, "\"password\"") == null);
    try testing.expect(std.mem.indexOf(u8, result, "\"api_key\"") == null);
    try testing.expect(std.mem.indexOf(u8, result, "\"id\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"username\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"email\"") != null);
}

test "Field filtering - nested field paths" {
    const allocator = testing.allocator;
    
    const json = 
        \\{
        \\  "user": {
        \\    "profile": {
        \\      "name": "John",
        \\      "age": 30,
        \\      "preferences": {
        \\        "theme": "dark",
        \\        "notifications": true
        \\      }
        \\    },
        \\    "credentials": {
        \\      "password": "secret",
        \\      "token": "xyz789"
        \\    }
        \\  },
        \\  "metadata": {
        \\    "created": "2024-01-01",
        \\    "updated": "2024-01-15"
        \\  }
        \\}
    ;
    
    // Parse the JSON
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    var token_stream = try parser.parseStreaming(json);
    defer token_stream.deinit();
    
    // Create pipeline with field filter
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    const include_fields = [_][]const u8{ 
        "user.profile.name",
        "user.profile.preferences",
        "metadata.created"
    };
    try pipeline.addTransformation(Transformation.init(.{
        .filter_fields = FilterConfig{
            .include = &include_fields,
        },
    }));
    
    // Execute transformation
    var output = OutputStream.init(allocator);
    defer output.deinit();
    
    try pipeline.executeStreaming(token_stream, &output);
    
    const result = output.getBuffer();
    
    // Verify nested paths are correctly filtered
    try testing.expect(std.mem.indexOf(u8, result, "\"name\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"preferences\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"theme\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"created\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"credentials\"") == null);
    try testing.expect(std.mem.indexOf(u8, result, "\"password\"") == null);
    try testing.expect(std.mem.indexOf(u8, result, "\"updated\"") == null);
}

test "Field filtering - wildcard patterns" {
    const allocator = testing.allocator;
    
    const json = 
        \\{
        \\  "user_id": 123,
        \\  "user_name": "john",
        \\  "user_email": "john@example.com",
        \\  "admin_level": 5,
        \\  "admin_permissions": ["read", "write"],
        \\  "system_config": {"debug": true},
        \\  "app_version": "1.0.0"
        \\}
    ;
    
    // Parse the JSON
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    var token_stream = try parser.parseStreaming(json);
    defer token_stream.deinit();
    
    // Create pipeline with field filter using wildcards
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    const include_fields = [_][]const u8{ "user_*", "app_*" };
    try pipeline.addTransformation(Transformation.init(.{
        .filter_fields = FilterConfig{
            .include = &include_fields,
        },
    }));
    
    // Execute transformation
    var output = OutputStream.init(allocator);
    defer output.deinit();
    
    try pipeline.executeStreaming(token_stream, &output);
    
    const result = output.getBuffer();
    
    // Verify wildcard matching
    try testing.expect(std.mem.indexOf(u8, result, "\"user_id\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"user_name\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"user_email\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"app_version\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"admin_level\"") == null);
    try testing.expect(std.mem.indexOf(u8, result, "\"admin_permissions\"") == null);
    try testing.expect(std.mem.indexOf(u8, result, "\"system_config\"") == null);
}

test "Field filtering - array handling" {
    const allocator = testing.allocator;
    
    const json = 
        \\{
        \\  "users": [
        \\    {
        \\      "id": 1,
        \\      "name": "Alice",
        \\      "password": "secret1"
        \\    },
        \\    {
        \\      "id": 2,
        \\      "name": "Bob",
        \\      "password": "secret2"
        \\    }
        \\  ],
        \\  "count": 2
        \\}
    ;
    
    // Parse the JSON
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    var token_stream = try parser.parseStreaming(json);
    defer token_stream.deinit();
    
    // Create pipeline with field filter
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    const exclude_fields = [_][]const u8{ "users.password" };
    try pipeline.addTransformation(Transformation.init(.{
        .filter_fields = FilterConfig{
            .exclude = &exclude_fields,
        },
    }));
    
    // Execute transformation
    var output = OutputStream.init(allocator);
    defer output.deinit();
    
    try pipeline.executeStreaming(token_stream, &output);
    
    const result = output.getBuffer();
    
    // Verify passwords are excluded from array elements
    try testing.expect(std.mem.indexOf(u8, result, "\"password\"") == null);
    try testing.expect(std.mem.indexOf(u8, result, "\"id\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"name\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"Alice\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"Bob\"") != null);
}

test "Field filtering - case insensitive matching" {
    const allocator = testing.allocator;
    
    const json = 
        \\{
        \\  "UserName": "john",
        \\  "userEmail": "john@example.com",
        \\  "USER_ID": 123
        \\}
    ;
    
    // Parse the JSON
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    var token_stream = try parser.parseStreaming(json);
    defer token_stream.deinit();
    
    // Create pipeline with case-insensitive field filter
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    const include_fields = [_][]const u8{ "username", "useremail" };
    try pipeline.addTransformation(Transformation.init(.{
        .filter_fields = FilterConfig{
            .include = &include_fields,
            .case_sensitive = false,
        },
    }));
    
    // Execute transformation
    var output = OutputStream.init(allocator);
    defer output.deinit();
    
    try pipeline.executeStreaming(token_stream, &output);
    
    const result = output.getBuffer();
    
    // Verify case-insensitive matching
    try testing.expect(std.mem.indexOf(u8, result, "\"UserName\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"userEmail\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"USER_ID\"") == null);
}