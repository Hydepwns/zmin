const std = @import("std");
const zmin = @import("zmin_lib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n=== zmin v2.0 Schema Validation Demo ===\n\n", .{});
    
    // Example 1: Basic type validation
    {
        std.debug.print("Example 1: Basic type validation\n", .{});
        
        // Create a simple schema for a string
        var string_schema = try zmin.v2.schema_validation.Schema.forString(allocator, 5, 50, .email);
        defer {
            string_schema.deinit();
            allocator.destroy(string_schema);
        }
        
        const validation_config = zmin.v2.schema_validation.ValidationConfig{
            .fail_fast = false,
            .validate_formats = true,
        };
        
        var validator = zmin.v2.schema_validation.SchemaValidator.init(
            allocator,
            string_schema,
            validation_config,
        );
        
        // Test valid email
        const valid_json = "\"user@example.com\"";
        std.debug.print("Validating: {s}\n", .{valid_json});
        
        var parser = try zmin.v2.StreamingParser.init(allocator, .{});
        defer parser.deinit();
        
        var token_stream = try parser.parseStreaming(valid_json);
        defer token_stream.deinit();
        
        var validation_state = try validator.validateTokenStream(&token_stream);
        defer validation_state.deinit();
        
        if (validation_state.isValid()) {
            std.debug.print("✅ Valid: Passed all validations\n", .{});
        } else {
            std.debug.print("❌ Invalid: Found {} errors\n", .{validation_state.getErrors().len});
            for (validation_state.getErrors()) |err| {
                std.debug.print("  Error: {s} at {s}\n", .{ err.message, err.instance_path });
            }
        }
        
        // Test invalid email (too short)
        const invalid_json = "\"hi\"";
        std.debug.print("\nValidating: {s}\n", .{invalid_json});
        
        var token_stream2 = try parser.parseStreaming(invalid_json);
        defer token_stream2.deinit();
        
        var validation_state2 = try validator.validateTokenStream(&token_stream2);
        defer validation_state2.deinit();
        
        if (validation_state2.isValid()) {
            std.debug.print("✅ Valid: Passed all validations\n", .{});
        } else {
            std.debug.print("❌ Invalid: Found {} errors\n", .{validation_state2.getErrors().len});
            for (validation_state2.getErrors()) |err| {
                std.debug.print("  Error: {s}\n", .{err.message});
            }
        }
        
        std.debug.print("\n");
    }
    
    // Example 2: Number validation with constraints
    {
        std.debug.print("Example 2: Number validation with constraints\n", .{});
        
        // Create a schema for numbers between 0 and 100, multiple of 5
        var number_schema = try zmin.v2.schema_validation.Schema.forNumber(allocator, 0, 100, 5);
        defer {
            number_schema.deinit();
            allocator.destroy(number_schema);
        }
        
        const validation_config = zmin.v2.schema_validation.ValidationConfig{
            .fail_fast = false,
        };
        
        var validator = zmin.v2.schema_validation.SchemaValidator.init(
            allocator,
            number_schema,
            validation_config,
        );
        
        var parser = try zmin.v2.StreamingParser.init(allocator, .{});
        defer parser.deinit();
        
        const test_numbers = [_][]const u8{ "25", "150", "7", "-5" };
        
        for (test_numbers) |num_json| {
            std.debug.print("Validating: {s}\n", .{num_json});
            
            var token_stream = try parser.parseStreaming(num_json);
            defer token_stream.deinit();
            
            var validation_state = try validator.validateTokenStream(&token_stream);
            defer validation_state.deinit();
            
            if (validation_state.isValid()) {
                std.debug.print("✅ Valid\n", .{});
            } else {
                std.debug.print("❌ Invalid: ", .{});
                const errors = validation_state.getErrors();
                for (errors, 0..) |err, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{err.message});
                }
                std.debug.print("\n", .{});
            }
        }
        
        std.debug.print("\n");
    }
    
    // Example 3: Object validation with required properties
    {
        std.debug.print("Example 3: Object validation with required properties\n", .{});
        
        // Create object schema with required properties
        const required_props = [_][]const u8{ "name", "age" };
        var object_schema = try zmin.v2.schema_validation.Schema.forObject(allocator, &required_props);
        defer {
            object_schema.deinit();
            allocator.destroy(object_schema);
        }
        
        // Add property schemas
        var name_schema = try zmin.v2.schema_validation.Schema.forString(allocator, 1, 50, .none);
        try object_schema.addProperty("name", name_schema);
        
        var age_schema = try zmin.v2.schema_validation.Schema.forNumber(allocator, 0, 150, null);
        try object_schema.addProperty("age", age_schema);
        
        const validation_config = zmin.v2.schema_validation.ValidationConfig{
            .fail_fast = false,
        };
        
        var validator = zmin.v2.schema_validation.SchemaValidator.init(
            allocator,
            object_schema,
            validation_config,
        );
        
        var parser = try zmin.v2.StreamingParser.init(allocator, .{});
        defer parser.deinit();
        
        // Test valid object
        const valid_object = 
            \\{
            \\  "name": "John Doe",
            \\  "age": 30,
            \\  "email": "john@example.com"
            \\}
        ;
        
        std.debug.print("Validating valid object:\n{s}\n", .{valid_object});
        
        var token_stream = try parser.parseStreaming(valid_object);
        defer token_stream.deinit();
        
        var validation_state = try validator.validateTokenStream(&token_stream);
        defer validation_state.deinit();
        
        if (validation_state.isValid()) {
            std.debug.print("✅ Valid: Object passes validation\n", .{});
        } else {
            std.debug.print("❌ Invalid: Found {} errors\n", .{validation_state.getErrors().len});
        }
        
        std.debug.print("Validated {} nodes\n", .{validation_state.nodes_validated});
        
        // Test object with type mismatch
        const invalid_object = 
            \\{
            \\  "name": "Jane Doe",
            \\  "age": "thirty"
            \\}
        ;
        
        std.debug.print("\nValidating object with type mismatch:\n{s}\n", .{invalid_object});
        
        var token_stream2 = try parser.parseStreaming(invalid_object);
        defer token_stream2.deinit();
        
        var validation_state2 = try validator.validateTokenStream(&token_stream2);
        defer validation_state2.deinit();
        
        if (validation_state2.isValid()) {
            std.debug.print("✅ Valid\n", .{});
        } else {
            std.debug.print("❌ Invalid: Found {} errors\n", .{validation_state2.getErrors().len});
            for (validation_state2.getErrors()) |err| {
                std.debug.print("  Error: {s}\n", .{err.message});
            }
        }
        
        std.debug.print("\n");
    }
    
    // Example 4: Streaming validation with transformation pipeline
    {
        std.debug.print("Example 4: Schema validation in transformation pipeline\n", .{});
        
        // Create a simple schema (this would normally be a JSON schema string)
        const simple_schema_json = 
            \\{
            \\  "type": "object",
            \\  "properties": {
            \\    "id": {"type": "number", "minimum": 1},
            \\    "name": {"type": "string", "minLength": 1},
            \\    "active": {"type": "boolean"}
            \\  },
            \\  "required": ["id", "name"]
            \\}
        ;
        
        // Initialize v2 streaming engine
        var engine = try zmin.v2.ZminEngine.init(allocator, .{});
        defer engine.deinit();
        
        // Add schema validation transformation
        try engine.addTransformation(zmin.v2.Transformation.init(.{
            .validate_schema = zmin.v2.SchemaConfig{
                .schema = simple_schema_json,
                .mode = .permissive, // Continue processing even with validation errors
            },
        }));
        
        // Test data with validation issues
        const test_data = 
            \\{
            \\  "id": 0,
            \\  "name": "",
            \\  "active": true,
            \\  "extra": "field"
            \\}
        ;
        
        std.debug.print("Processing data with schema validation:\n{s}\n", .{test_data});
        
        const result = try engine.processToString(allocator, test_data);
        defer allocator.free(result);
        
        std.debug.print("Processed result: {s}\n", .{result});
        
        const stats = engine.getStats();
        std.debug.print("Validation stats: {} errors, {} nodes validated\n", .{
            stats.validation_errors,
            stats.nodes_validated,
        });
        
        std.debug.print("\n");
    }
    
    // Example 5: Format validation
    {
        std.debug.print("Example 5: String format validation\n", .{});
        
        const formats = [_]zmin.v2.schema_validation.StringFormat{ .email, .uri, .uuid, .date, .ipv4 };
        const test_values = [_][]const u8{
            "\"user@example.com\"",
            "\"https://example.com\"", 
            "\"123e4567-e89b-12d3-a456-426614174000\"",
            "\"2023-12-25\"",
            "\"192.168.1.1\"",
        };
        
        var parser = try zmin.v2.StreamingParser.init(allocator, .{});
        defer parser.deinit();
        
        for (formats, test_values, 0..) |format, test_value, i| {
            std.debug.print("Testing {s} format with: {s}\n", .{ @tagName(format), test_value });
            
            var string_schema = try zmin.v2.schema_validation.Schema.forString(allocator, null, null, format);
            defer {
                string_schema.deinit();
                allocator.destroy(string_schema);
            }
            
            const validation_config = zmin.v2.schema_validation.ValidationConfig{
                .validate_formats = true,
            };
            
            var validator = zmin.v2.schema_validation.SchemaValidator.init(
                allocator,
                string_schema,
                validation_config,
            );
            
            var token_stream = try parser.parseStreaming(test_value);
            defer token_stream.deinit();
            
            var validation_state = try validator.validateTokenStream(&token_stream);
            defer validation_state.deinit();
            
            if (validation_state.isValid()) {
                std.debug.print("✅ Valid format\n", .{});
            } else {
                std.debug.print("❌ Invalid format\n", .{});
            }
            
            if (i < formats.len - 1) std.debug.print("\n", .{});
        }
    }
    
    std.debug.print("\n✅ Schema validation demonstration complete!\n");
}