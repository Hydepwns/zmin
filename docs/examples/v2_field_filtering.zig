const std = @import("std");
const zmin = @import("zmin_lib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n=== zmin v2.0 Field Filtering Demo ===\n\n", .{});
    
    // Sample JSON with sensitive data
    const json_data = 
        \\{
        \\  "user": {
        \\    "id": 12345,
        \\    "username": "johndoe",
        \\    "email": "john@example.com",
        \\    "profile": {
        \\      "firstName": "John",
        \\      "lastName": "Doe",
        \\      "age": 30,
        \\      "preferences": {
        \\        "theme": "dark",
        \\        "language": "en",
        \\        "notifications": true
        \\      }
        \\    },
        \\    "security": {
        \\      "password": "hashed_password_123",
        \\      "apiKey": "sk-1234567890abcdef",
        \\      "refreshToken": "rt-abcdef123456",
        \\      "mfaSecret": "JBSWY3DPEHPK3PXP"
        \\    },
        \\    "billing": {
        \\      "cardNumber": "4111-1111-1111-1111",
        \\      "cvv": "123",
        \\      "expiryDate": "12/25"
        \\    }
        \\  },
        \\  "metadata": {
        \\    "created": "2024-01-01T10:00:00Z",
        \\    "updated": "2024-08-01T15:30:00Z",
        \\    "version": "2.0"
        \\  }
        \\}
    ;
    
    // Initialize v2 streaming engine
    const engine = try zmin.v2.ZminEngine.init(allocator, .{});
    defer engine.deinit();
    
    std.debug.print("Original JSON size: {} bytes\n\n", .{json_data.len});
    
    // Example 1: Exclude sensitive fields
    {
        std.debug.print("Example 1: Excluding sensitive fields\n", .{});
        std.debug.print("Excluding: password, apiKey, refreshToken, mfaSecret, billing\n", .{});
        
        const exclude_fields = [_][]const u8{
            "user.security",
            "user.billing",
        };
        
        const filter_config = zmin.v2.TransformationPipeline.FilterConfig{
            .exclude = &exclude_fields,
        };
        
        const transformation = zmin.v2.TransformationPipeline.Transformation.init(.{
            .filter_fields = filter_config,
        });
        
        const result = try engine.transformWithConfig(allocator, json_data, &[_]zmin.v2.TransformationPipeline.Transformation{transformation});
        defer allocator.free(result);
        
        std.debug.print("Result ({} bytes):\n{s}\n\n", .{ result.len, result });
    }
    
    // Example 2: Include only specific fields
    {
        std.debug.print("Example 2: Including only specific fields\n", .{});
        std.debug.print("Including: user.id, user.username, user.email, metadata.version\n", .{});
        
        const include_fields = [_][]const u8{
            "user.id",
            "user.username", 
            "user.email",
            "metadata.version",
        };
        
        const filter_config = zmin.v2.TransformationPipeline.FilterConfig{
            .include = &include_fields,
        };
        
        const transformation = zmin.v2.TransformationPipeline.Transformation.init(.{
            .filter_fields = filter_config,
        });
        
        const result = try engine.transformWithConfig(allocator, json_data, &[_]zmin.v2.TransformationPipeline.Transformation{transformation});
        defer allocator.free(result);
        
        std.debug.print("Result ({} bytes):\n{s}\n\n", .{ result.len, result });
    }
    
    // Example 3: Using wildcard patterns
    {
        std.debug.print("Example 3: Using wildcard patterns\n", .{});
        std.debug.print("Including: user.profile.*, metadata.*\n", .{});
        
        const include_fields = [_][]const u8{
            "user.profile.*",
            "metadata.*",
        };
        
        const filter_config = zmin.v2.TransformationPipeline.FilterConfig{
            .include = &include_fields,
        };
        
        const transformation = zmin.v2.TransformationPipeline.Transformation.init(.{
            .filter_fields = filter_config,
        });
        
        const result = try engine.transformWithConfig(allocator, json_data, &[_]zmin.v2.TransformationPipeline.Transformation{transformation});
        defer allocator.free(result);
        
        std.debug.print("Result ({} bytes):\n{s}\n\n", .{ result.len, result });
    }
    
    // Example 4: Field filtering with minification
    {
        std.debug.print("Example 4: Combining field filtering with minification\n", .{});
        std.debug.print("Excluding sensitive fields + minifying output\n", .{});
        
        const exclude_fields = [_][]const u8{
            "user.security",
            "user.billing",
        };
        
        const transformations = [_]zmin.v2.TransformationPipeline.Transformation{
            zmin.v2.TransformationPipeline.Transformation.init(.{
                .filter_fields = .{ .exclude = &exclude_fields },
            }).withPriority(1),
            zmin.v2.TransformationPipeline.Transformation.init(.{
                .minify = .{ .remove_whitespace = true },
            }).withPriority(2),
        };
        
        const result = try engine.transformWithConfig(allocator, json_data, &transformations);
        defer allocator.free(result);
        
        std.debug.print("Result ({} bytes):\n{s}\n\n", .{ result.len, result });
    }
    
    // Performance benchmark
    {
        std.debug.print("Performance Benchmark:\n", .{});
        
        // Generate larger JSON for benchmarking
        var large_json = std.ArrayList(u8).init(allocator);
        defer large_json.deinit();
        
        try large_json.appendSlice("{\n  \"users\": [\n");
        for (0..1000) |i| {
            try large_json.writer().print(
                \\    {{
                \\      "id": {},
                \\      "username": "user{}",
                \\      "email": "user{}@example.com",
                \\      "password": "secret{}",
                \\      "apiKey": "key-{}-abcdef",
                \\      "profile": {{
                \\        "name": "User {}",
                \\        "age": {},
                \\        "active": {}
                \\      }}
                \\    }}
            , .{ i, i, i, i, i, i, i % 100, if (i % 2 == 0) "true" else "false" });
            
            if (i < 999) try large_json.appendSlice(",\n");
        }
        try large_json.appendSlice("\n  ]\n}");
        
        const large_data = large_json.items;
        std.debug.print("  Test data size: {} KB\n", .{large_data.len / 1024});
        
        // Benchmark filtering performance
        const exclude_fields = [_][]const u8{ "users.password", "users.apiKey" };
        const filter_config = zmin.v2.TransformationPipeline.FilterConfig{
            .exclude = &exclude_fields,
        };
        const transformation = zmin.v2.TransformationPipeline.Transformation.init(.{
            .filter_fields = filter_config,
        });
        
        const start_time = std.time.nanoTimestamp();
        const result = try engine.transformWithConfig(allocator, large_data, 
            &[_]zmin.v2.TransformationPipeline.Transformation{transformation});
        defer allocator.free(result);
        const end_time = std.time.nanoTimestamp();
        
        const elapsed_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const throughput_mbps = (@as(f64, @floatFromInt(large_data.len)) / 1024.0 / 1024.0) / (elapsed_ms / 1000.0);
        
        std.debug.print("  Processing time: {d:.2} ms\n", .{elapsed_ms});
        std.debug.print("  Throughput: {d:.2} MB/s\n", .{throughput_mbps});
        std.debug.print("  Output size: {} KB ({}% reduction)\n", .{
            result.len / 1024,
            100 - (result.len * 100 / large_data.len),
        });
    }
    
    std.debug.print("\n✅ Field filtering transformation implemented successfully!\n", .{});
}