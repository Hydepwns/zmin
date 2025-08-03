const std = @import("std");
const testing = std.testing;
const schema_validation = @import("src/v2/schema_validation.zig");

test "Schema creation and type validation" {
    const allocator = testing.allocator;
    
    // Test string schema
    var string_schema = try schema_validation.Schema.forString(allocator, 5, 50, .email);
    defer {
        string_schema.deinit();
        allocator.destroy(string_schema);
    }
    
    try testing.expect(string_schema.schema_type.? == .string);
    try testing.expect(string_schema.min_length.? == 5);
    try testing.expect(string_schema.max_length.? == 50);
    try testing.expect(string_schema.format == .email);
}

test "Number schema with constraints" {
    const allocator = testing.allocator;
    
    var number_schema = try schema_validation.Schema.forNumber(allocator, 0, 100, 5);
    defer {
        number_schema.deinit();
        allocator.destroy(number_schema);
    }
    
    try testing.expect(number_schema.schema_type.? == .number);
    try testing.expect(number_schema.minimum.? == 0);
    try testing.expect(number_schema.maximum.? == 100);
    try testing.expect(number_schema.multiple_of.? == 5);
}

test "Object schema with properties" {
    const allocator = testing.allocator;
    
    const required = [_][]const u8{"name", "age"};
    var object_schema = try schema_validation.Schema.forObject(allocator, &required);
    defer {
        object_schema.deinit();
        allocator.destroy(object_schema);
    }
    
    // Add property schemas
    var name_schema = try schema_validation.Schema.forString(allocator, 1, 50, .none);
    try object_schema.addProperty("name", name_schema);
    
    var age_schema = try schema_validation.Schema.forNumber(allocator, 0, 150, null);
    try object_schema.addProperty("age", age_schema);
    
    try testing.expect(object_schema.schema_type.? == .object);
    try testing.expect(object_schema.required != null);
    try testing.expect(object_schema.required.?.len == 2);
    try testing.expect(object_schema.properties != null);
}

test "ValidationConfig and ValidatorState" {
    const allocator = testing.allocator;
    
    const config = schema_validation.ValidationConfig{
        .fail_fast = true,
        .max_errors = 50,
        .validate_formats = true,
    };
    
    var state = schema_validation.ValidatorState.init(allocator, config);
    defer state.deinit();
    
    try testing.expect(state.isValid());
    try testing.expect(state.getErrors().len == 0);
    
    // Test path tracking
    try state.path_stack.append("user");
    try state.path_stack.append("profile");
    
    const path = try state.getCurrentPath();
    defer allocator.free(path);
    
    try testing.expect(std.mem.eql(u8, path, "/user/profile"));
}

test "String format validation" {
    const allocator = testing.allocator;
    
    var string_schema = try schema_validation.Schema.forString(allocator, null, null, .email);
    defer {
        string_schema.deinit();
        allocator.destroy(string_schema);
    }
    
    const config = schema_validation.ValidationConfig{
        .validate_formats = true,
    };
    
    var validator = schema_validation.SchemaValidator.init(allocator, string_schema, config);
    
    // Test valid email format
    try testing.expect(try validator.validateStringFormat("user@example.com", .email));
    
    // Test invalid email format
    try testing.expect(!try validator.validateStringFormat("invalid-email", .email));
    
    // Test URI format
    try testing.expect(try validator.validateStringFormat("https://example.com", .uri));
    try testing.expect(!try validator.validateStringFormat("not-a-uri", .uri));
    
    // Test UUID format
    try testing.expect(try validator.validateStringFormat("123e4567-e89b-12d3-a456-426614174000", .uuid));
    try testing.expect(!try validator.validateStringFormat("invalid-uuid", .uuid));
    
    // Test date format
    try testing.expect(try validator.validateStringFormat("2023-12-25", .date));
    try testing.expect(!try validator.validateStringFormat("invalid-date", .date));
    
    // Test IPv4 format
    try testing.expect(try validator.validateStringFormat("192.168.1.1", .ipv4));
    try testing.expect(!try validator.validateStringFormat("999.999.999.999", .ipv4));
}

test "Error accumulation" {
    const allocator = testing.allocator;
    
    const config = schema_validation.ValidationConfig{
        .fail_fast = false,
        .max_errors = 10,
        .collect_errors = true,
    };
    
    var state = schema_validation.ValidatorState.init(allocator, config);
    defer state.deinit();
    
    // Add some test errors
    try state.addError("First error", 10, "expected", "actual");
    try state.addError("Second error", 20, null, null);
    
    try testing.expect(!state.isValid());
    try testing.expect(state.getErrors().len == 2);
    
    const errors = state.getErrors();
    try testing.expect(std.mem.eql(u8, errors[0].message, "First error"));
    try testing.expect(errors[0].position == 10);
    try testing.expect(std.mem.eql(u8, errors[1].message, "Second error"));
    try testing.expect(errors[1].position == 20);
}