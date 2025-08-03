const std = @import("std");
const testing = std.testing;
const StreamingParser = @import("src/v2/streaming/parser.zig").StreamingParser;
const TransformationPipeline = @import("src/v2/transformations/pipeline.zig").TransformationPipeline;
const OutputStream = @import("src/v2/transformations/pipeline.zig").OutputStream;
const Transformation = @import("src/v2/transformations/pipeline.zig").Transformation;
const TransformationConfig = @import("src/v2/transformations/pipeline.zig").TransformationConfig;
const FilterConfig = @import("src/v2/transformations/pipeline.zig").FilterConfig;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
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
    
    std.debug.print("Result:\n{s}\n", .{result});
    std.debug.print("\nChecking fields:\n", .{});
    std.debug.print("  name: {}\n", .{std.mem.indexOf(u8, result, "\"name\"") != null});
    std.debug.print("  preferences: {}\n", .{std.mem.indexOf(u8, result, "\"preferences\"") != null});
    std.debug.print("  theme: {}\n", .{std.mem.indexOf(u8, result, "\"theme\"") != null});
    std.debug.print("  created: {}\n", .{std.mem.indexOf(u8, result, "\"created\"") != null});
    std.debug.print("  credentials: {}\n", .{std.mem.indexOf(u8, result, "\"credentials\"") == null});
    std.debug.print("  password: {}\n", .{std.mem.indexOf(u8, result, "\"password\"") == null});
}