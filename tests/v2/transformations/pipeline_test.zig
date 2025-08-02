const std = @import("std");
const testing = std.testing;
const v2 = @import("src").v2;
const TransformationPipeline = v2.TransformationPipeline;
const Transformation = v2.Transformation;
const TransformationConfig = v2.TransformationConfig;
const MinifyConfig = v2.MinifyConfig;
const FilterFieldsConfig = v2.FilterFieldsConfig;
const SchemaValidationConfig = v2.SchemaValidationConfig;
const FormatConversionConfig = v2.FormatConversionConfig;
const StreamingParser = v2.StreamingParser;
const OutputStream = v2.OutputStream;

test "TransformationPipeline.init - creates empty pipeline" {
    const allocator = testing.allocator;
    
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    try testing.expectEqual(@as(usize, 0), pipeline.transformations.items.len);
    try testing.expectEqual(@as(u64, 0), pipeline.stats.transformations_applied);
    try testing.expectEqual(@as(u64, 0), pipeline.stats.bytes_processed);
}

test "TransformationPipeline.addTransformation - adds transformations with priority" {
    const allocator = testing.allocator;
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    // Add transformations with different priorities
    try pipeline.addTransformation(.{
        .name = "minify",
        .config = .{ .minify = .{ .remove_whitespace = true } },
        .priority = 10,
    });
    
    try pipeline.addTransformation(.{
        .name = "filter",
        .config = .{ .filter_fields = .{
            .include = &[_][]const u8{"name", "value"},
            .exclude = &[_][]const u8{},
        }},
        .priority = 5,
    });
    
    try testing.expectEqual(@as(usize, 2), pipeline.transformations.items.len);
    
    // Check that transformations are sorted by priority
    try testing.expect(pipeline.transformations.items[0].priority < pipeline.transformations.items[1].priority);
}

test "TransformationPipeline.executeStreaming - minification transformation" {
    const allocator = testing.allocator;
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    // Add minification transformation
    try pipeline.addTransformation(.{
        .name = "minify",
        .config = .{ .minify = .{
            .remove_whitespace = true,
            .remove_quotes_from_keys = false,
        }},
        .priority = 1,
    });
    
    // Create parser and parse input
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "{ \"name\" : \"test\" , \"value\" : 123 }";
    const token_stream = try parser.parseStreaming(input);
    
    // Create output stream
    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    
    var output = OutputStream{
        .writer = output_buffer.writer().any(),
        .bytes_written = 0,
    };
    
    // Execute pipeline
    try pipeline.executeStreaming(token_stream, &output);
    
    // Check minified output
    const result = output_buffer.items;
    try testing.expectEqualStrings("{\"name\":\"test\",\"value\":123}", result);
    try testing.expect(pipeline.stats.transformations_applied > 0);
}

test "TransformationPipeline.executeStreaming - multiple transformations" {
    const allocator = testing.allocator;
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    // Add multiple transformations
    try pipeline.addTransformation(.{
        .name = "filter",
        .config = .{ .filter_fields = .{
            .include = &[_][]const u8{"important"},
            .exclude = &[_][]const u8{},
        }},
        .priority = 1,
    });
    
    try pipeline.addTransformation(.{
        .name = "minify",
        .config = .{ .minify = .{ .remove_whitespace = true } },
        .priority = 2,
    });
    
    // Create parser and parse input
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "{ \"important\" : true , \"extra\" : \"remove\" }";
    const token_stream = try parser.parseStreaming(input);
    
    // Create output stream
    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    
    var output = OutputStream{
        .writer = output_buffer.writer().any(),
        .bytes_written = 0,
    };
    
    // Execute pipeline
    try pipeline.executeStreaming(token_stream, &output);
    
    // Should filter and minify
    const result = output_buffer.items;
    try testing.expectEqualStrings("{\"important\":true}", result);
}

test "TransformationPipeline.removeTransformation - removes by name" {
    const allocator = testing.allocator;
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    // Add transformations
    try pipeline.addTransformation(.{
        .name = "minify",
        .config = .{ .minify = .{ .remove_whitespace = true } },
        .priority = 1,
    });
    
    try pipeline.addTransformation(.{
        .name = "filter",
        .config = .{ .filter_fields = .{
            .include = &[_][]const u8{},
            .exclude = &[_][]const u8{},
        }},
        .priority = 2,
    });
    
    try testing.expectEqual(@as(usize, 2), pipeline.transformations.items.len);
    
    // Remove one transformation
    try pipeline.removeTransformation("filter");
    
    try testing.expectEqual(@as(usize, 1), pipeline.transformations.items.len);
    try testing.expectEqualStrings("minify", pipeline.transformations.items[0].name);
}

test "TransformationPipeline.clearTransformations - removes all" {
    const allocator = testing.allocator;
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    // Add multiple transformations
    try pipeline.addTransformation(.{
        .name = "transform1",
        .config = .{ .minify = .{ .remove_whitespace = true } },
        .priority = 1,
    });
    
    try pipeline.addTransformation(.{
        .name = "transform2",
        .config = .{ .minify = .{ .remove_whitespace = true } },
        .priority = 2,
    });
    
    try testing.expectEqual(@as(usize, 2), pipeline.transformations.items.len);
    
    // Clear all
    pipeline.clearTransformations();
    
    try testing.expectEqual(@as(usize, 0), pipeline.transformations.items.len);
}

test "TransformationPipeline.getStats - tracks statistics" {
    const allocator = testing.allocator;
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    // Initial stats
    var stats = pipeline.getStats();
    try testing.expectEqual(@as(u64, 0), stats.transformations_applied);
    try testing.expectEqual(@as(u64, 0), stats.bytes_processed);
    
    // Add transformation and process
    try pipeline.addTransformation(.{
        .name = "minify",
        .config = .{ .minify = .{ .remove_whitespace = true } },
        .priority = 1,
    });
    
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "{ \"test\" : true }";
    const token_stream = try parser.parseStreaming(input);
    
    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    
    var output = OutputStream{
        .writer = output_buffer.writer().any(),
        .bytes_written = 0,
    };
    
    try pipeline.executeStreaming(token_stream, &output);
    
    // Check updated stats
    stats = pipeline.getStats();
    try testing.expect(stats.transformations_applied > 0);
    try testing.expect(stats.bytes_processed > 0);
}

test "TransformationPipeline.optimizePipeline - placeholder for optimization" {
    const allocator = testing.allocator;
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    // Add transformations
    try pipeline.addTransformation(.{
        .name = "transform1",
        .config = .{ .minify = .{ .remove_whitespace = true } },
        .priority = 1,
    });
    
    // Call optimize (currently a no-op)
    try pipeline.optimizePipeline();
    
    // Should not crash
    try testing.expect(true);
}

test "TransformationPipeline - custom transformation" {
    const allocator = testing.allocator;
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    // Define custom transformation function
    const CustomData = struct {
        count: usize = 0,
    };
    
    var custom_data = CustomData{};
    
    const customTransform = struct {
        fn transform(
            token: *const v2.Token,
            input: []const u8,
            output: *OutputStream,
            user_data: ?*anyopaque,
        ) !bool {
            _ = input;
            
            // Count tokens
            if (user_data) |data| {
                const typed_data = @as(*CustomData, @ptrCast(@alignCast(data)));
                typed_data.count += 1;
            }
            
            // Write token representation
            try output.writer.print("<{s}>", .{@tagName(token.token_type)});
            
            return true; // Continue processing
        }
    }.transform;
    
    // Add custom transformation
    try pipeline.addTransformation(.{
        .name = "custom",
        .config = .{ .custom = .{
            .transform = customTransform,
            .user_data = &custom_data,
            .cleanup = null,
        }},
        .priority = 1,
    });
    
    // Process input
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "[1,2,3]";
    const token_stream = try parser.parseStreaming(input);
    
    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    
    var output = OutputStream{
        .writer = output_buffer.writer().any(),
        .bytes_written = 0,
    };
    
    try pipeline.executeStreaming(token_stream, &output);
    
    // Check custom transformation was applied
    try testing.expect(custom_data.count > 0);
    try testing.expect(output_buffer.items.len > 0);
}

test "TransformationPipeline - schema validation configuration" {
    const allocator = testing.allocator;
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    // Add schema validation transformation
    const schema = 
        \\{
        \\  "type": "object",
        \\  "properties": {
        \\    "name": {"type": "string"},
        \\    "age": {"type": "number"}
        \\  }
        \\}
    ;
    
    try pipeline.addTransformation(.{
        .name = "validate",
        .config = .{ .validate_schema = .{
            .schema = schema,
            .strict = true,
        }},
        .priority = 1,
    });
    
    try testing.expectEqual(@as(usize, 1), pipeline.transformations.items.len);
}

test "TransformationPipeline - format conversion configuration" {
    const allocator = testing.allocator;
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    // Add format conversion transformation
    try pipeline.addTransformation(.{
        .name = "convert",
        .config = .{ .convert_format = .{
            .target_format = .msgpack,
            .options = .{},
        }},
        .priority = 1,
    });
    
    try testing.expectEqual(@as(usize, 1), pipeline.transformations.items.len);
}

test "ParallelExecutor - basic initialization" {
    const allocator = testing.allocator;
    
    var executor = try v2.ParallelExecutor.init(allocator, 4);
    defer executor.deinit();
    
    try testing.expectEqual(@as(usize, 4), executor.workers.items.len);
}

test "ParallelExecutor.executeParallel - delegates to pipeline" {
    const allocator = testing.allocator;
    
    var executor = try v2.ParallelExecutor.init(allocator, 2);
    defer executor.deinit();
    
    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();
    
    // Add simple transformation
    try pipeline.addTransformation(.{
        .name = "minify",
        .config = .{ .minify = .{ .remove_whitespace = true } },
        .priority = 1,
    });
    
    // Parse input
    var parser = try StreamingParser.init(allocator, .{});
    defer parser.deinit();
    
    const input = "{ \"parallel\" : true }";
    const token_stream = try parser.parseStreaming(input);
    
    // Execute in parallel (currently delegates to sequential)
    var output_buffer = std.ArrayList(u8).init(allocator);
    defer output_buffer.deinit();
    
    var output = OutputStream{
        .writer = output_buffer.writer().any(),
        .bytes_written = 0,
    };
    
    try executor.executeParallel(&pipeline, token_stream, &output);
    
    // Should produce output
    try testing.expect(output_buffer.items.len > 0);
}