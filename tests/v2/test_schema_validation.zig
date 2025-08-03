const std = @import("std");
const schema_validation = @import("src/v2/schema_validation.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    std.debug.print("Testing Schema Validation System...\n", .{});
    
    // Test 1: String schema creation
    {
        var string_schema = try schema_validation.Schema.forString(allocator, 5, 50, .email);
        defer {
            string_schema.deinit();
            allocator.destroy(string_schema);
        }
        
        std.debug.print("Test 1 - String schema creation: ", .{});
        if (string_schema.schema_type.? == .string and 
            string_schema.min_length.? == 5 and 
            string_schema.max_length.? == 50 and 
            string_schema.format == .email) {
            std.debug.print("PASS\n", .{});
        } else {
            std.debug.print("FAIL\n", .{});
        }
    }
    
    // Test 2: Number schema with constraints  
    {
        var number_schema = try schema_validation.Schema.forNumber(allocator, 0, 100, 5);
        defer {
            number_schema.deinit();
            allocator.destroy(number_schema);
        }
        
        std.debug.print("Test 2 - Number schema creation: ", .{});
        if (number_schema.schema_type.? == .number and
            number_schema.minimum.? == 0 and
            number_schema.maximum.? == 100 and
            number_schema.multiple_of.? == 5) {
            std.debug.print("PASS\n", .{});
        } else {
            std.debug.print("FAIL\n", .{});
        }
    }
    
    // Test 3: Object schema with properties
    {
        const required = [_][]const u8{"name", "age"};
        var object_schema = try schema_validation.Schema.forObject(allocator, required[0..]);
        defer {
            object_schema.deinit();
            allocator.destroy(object_schema);
        }
        
        // Add property schemas
        const name_schema = try schema_validation.Schema.forString(allocator, 1, 50, .none);
        try object_schema.addProperty("name", name_schema);
        
        const age_schema = try schema_validation.Schema.forNumber(allocator, 0, 150, null);
        try object_schema.addProperty("age", age_schema);
        
        std.debug.print("Test 3 - Object schema with properties: ", .{});
        if (object_schema.schema_type.? == .object and
            object_schema.required != null and
            object_schema.required.?.len == 2 and
            object_schema.properties != null) {
            std.debug.print("PASS\n", .{});
        } else {
            std.debug.print("FAIL\n", .{});
        }
    }
    
    // Test 4: Validator state management
    {
        const config = schema_validation.ValidationConfig{
            .fail_fast = true,
            .max_errors = 50,
            .validate_formats = true,
        };
        
        var state = schema_validation.ValidatorState.init(allocator, config);
        defer state.deinit();
        
        try state.path_stack.append("user");
        try state.path_stack.append("profile");
        
        const path = try state.getCurrentPath();
        defer allocator.free(path);
        
        std.debug.print("Test 4 - Validator state management: ", .{});
        if (state.isValid() and 
            state.getErrors().len == 0 and
            std.mem.eql(u8, path, "/user/profile")) {
            std.debug.print("PASS\n", .{});
        } else {
            std.debug.print("FAIL (path: {s})\n", .{path});
        }
    }
    
    // Test 5: String format validation
    {
        var string_schema = try schema_validation.Schema.forString(allocator, null, null, .email);
        defer {
            string_schema.deinit();
            allocator.destroy(string_schema);
        }
        
        const config = schema_validation.ValidationConfig{
            .validate_formats = true,
        };
        
        var validator = schema_validation.SchemaValidator.init(allocator, string_schema, config);
        
        std.debug.print("Test 5 - String format validation: ", .{});
        
        // Test various format validations
        const email_valid = try validator.validateStringFormat("user@example.com", .email);
        const email_invalid = try validator.validateStringFormat("invalid-email", .email);
        const uri_valid = try validator.validateStringFormat("https://example.com", .uri);
        const uuid_valid = try validator.validateStringFormat("123e4567-e89b-12d3-a456-426614174000", .uuid);
        const date_valid = try validator.validateStringFormat("2023-12-25", .date);
        const ipv4_valid = try validator.validateStringFormat("192.168.1.1", .ipv4);
        
        if (email_valid and !email_invalid and uri_valid and uuid_valid and date_valid and ipv4_valid) {
            std.debug.print("PASS\n", .{});
        } else {
            std.debug.print("FAIL (email: {}, uri: {}, uuid: {}, date: {}, ipv4: {})\n", .{
                email_valid, uri_valid, uuid_valid, date_valid, ipv4_valid
            });
        }
    }
    
    // Test 6: Error handling
    {
        const config = schema_validation.ValidationConfig{
            .fail_fast = false,
            .max_errors = 10,
        };
        
        var state = schema_validation.ValidatorState.init(allocator, config);
        defer state.deinit();
        
        // Add test errors
        try state.addError("Test error 1", 10, "expected", "actual");
        try state.addError("Test error 2", 20, null, null);
        
        std.debug.print("Test 6 - Error handling: ", .{});
        if (!state.isValid() and state.getErrors().len == 2) {
            const errors = state.getErrors();
            if (std.mem.eql(u8, errors[0].message, "Test error 1") and 
                errors[0].position == 10 and
                std.mem.eql(u8, errors[1].message, "Test error 2") and
                errors[1].position == 20) {
                std.debug.print("PASS\n", .{});
            } else {
                std.debug.print("FAIL (error details)\n", .{});
            }
        } else {
            std.debug.print("FAIL (error count: {})\n", .{state.getErrors().len});
        }
    }
    
    std.debug.print("\nSchema validation system tests completed!\n", .{});
}