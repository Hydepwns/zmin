const std = @import("std");
const testing = std.testing;

// Import the minifier components directly
const types = @import("src/minifier/types.zig");
const MinifyingParser = types.MinifyingParser;

// ========== REAL-WORLD JSON SAMPLES ==========

test "integration - package.json style" {
    const input =
        \\{
        \\  "name": "json-minifier",
        \\  "version": "1.0.0",
        \\  "description": "High-performance JSON minifier",
        \\  "main": "src/main.zig",
        \\  "scripts": {
        \\    "build": "zig build",
        \\    "test": "zig build test",
        \\    "benchmark": "zig build benchmark"
        \\  },
        \\  "keywords": ["json", "minifier", "performance"],
        \\  "author": "Test Author",
        \\  "license": "MIT",
        \\  "dependencies": {},
        \\  "devDependencies": {
        \\    "test-framework": "^1.0.0"
        \\  }
        \\}
    ;

    const expected = "{\"name\":\"json-minifier\",\"version\":\"1.0.0\",\"description\":\"High-performance JSON minifier\",\"main\":\"src/main.zig\",\"scripts\":{\"build\":\"zig build\",\"test\":\"zig build test\",\"benchmark\":\"zig build benchmark\"},\"keywords\":[\"json\",\"minifier\",\"performance\"],\"author\":\"Test Author\",\"license\":\"MIT\",\"dependencies\":{},\"devDependencies\":{\"test-framework\":\"^1.0.0\"}}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "integration - API response style" {
    const input =
        \\{
        \\  "status": "success",
        \\  "data": {
        \\    "users": [
        \\      {
        \\        "id": 1,
        \\        "username": "john_doe",
        \\        "email": "john@example.com",
        \\        "profile": {
        \\          "firstName": "John",
        \\          "lastName": "Doe",
        \\          "age": 28,
        \\          "location": "New York, NY",
        \\          "verified": true
        \\        },
        \\        "preferences": {
        \\          "notifications": true,
        \\          "theme": "dark",
        \\          "language": "en"
        \\        }
        \\      },
        \\      {
        \\        "id": 2,
        \\        "username": "jane_smith",
        \\        "email": "jane@example.com",
        \\        "profile": {
        \\          "firstName": "Jane",
        \\          "lastName": "Smith",
        \\          "age": null,
        \\          "location": "San Francisco, CA",
        \\          "verified": false
        \\        },
        \\        "preferences": {
        \\          "notifications": false,
        \\          "theme": "light",
        \\          "language": "en"
        \\        }
        \\      }
        \\    ],
        \\    "pagination": {
        \\      "page": 1,
        \\      "limit": 10,
        \\      "total": 2,
        \\      "hasNext": false
        \\    }
        \\  },
        \\  "timestamp": "2023-12-01T10:30:00Z",
        \\  "requestId": "req-12345-abcde"
        \\}
    ;

    const expected = "{\"status\":\"success\",\"data\":{\"users\":[{\"id\":1,\"username\":\"john_doe\",\"email\":\"john@example.com\",\"profile\":{\"firstName\":\"John\",\"lastName\":\"Doe\",\"age\":28,\"location\":\"New York, NY\",\"verified\":true},\"preferences\":{\"notifications\":true,\"theme\":\"dark\",\"language\":\"en\"}},{\"id\":2,\"username\":\"jane_smith\",\"email\":\"jane@example.com\",\"profile\":{\"firstName\":\"Jane\",\"lastName\":\"Smith\",\"age\":null,\"location\":\"San Francisco, CA\",\"verified\":false},\"preferences\":{\"notifications\":false,\"theme\":\"light\",\"language\":\"en\"}}],\"pagination\":{\"page\":1,\"limit\":10,\"total\":2,\"hasNext\":false}},\"timestamp\":\"2023-12-01T10:30:00Z\",\"requestId\":\"req-12345-abcde\"}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "integration - configuration file style" {
    const input =
        \\{
        \\  "database": {
        \\    "host": "localhost",
        \\    "port": 5432,
        \\    "name": "myapp_db",
        \\    "username": "dbuser",
        \\    "password": "secret123",
        \\    "ssl": true,
        \\    "pool": {
        \\      "min": 5,
        \\      "max": 20,
        \\      "timeout": 30000
        \\    }
        \\  },
        \\  "redis": {
        \\    "host": "127.0.0.1",
        \\    "port": 6379,
        \\    "db": 0,
        \\    "ttl": 3600
        \\  },
        \\  "server": {
        \\    "host": "0.0.0.0",
        \\    "port": 8080,
        \\    "workers": 4,
        \\    "cors": {
        \\      "enabled": true,
        \\      "origins": ["http://localhost:3000", "https://myapp.com"],
        \\      "methods": ["GET", "POST", "PUT", "DELETE"],
        \\      "headers": ["Content-Type", "Authorization"]
        \\    }
        \\  },
        \\  "logging": {
        \\    "level": "info",
        \\    "format": "json",
        \\    "outputs": ["console", "file"],
        \\    "file": {
        \\      "path": "/var/log/myapp.log",
        \\      "maxSize": "100MB",
        \\      "rotate": true
        \\    }
        \\  }
        \\}
    ;

    const expected = "{\"database\":{\"host\":\"localhost\",\"port\":5432,\"name\":\"myapp_db\",\"username\":\"dbuser\",\"password\":\"secret123\",\"ssl\":true,\"pool\":{\"min\":5,\"max\":20,\"timeout\":30000}},\"redis\":{\"host\":\"127.0.0.1\",\"port\":6379,\"db\":0,\"ttl\":3600},\"server\":{\"host\":\"0.0.0.0\",\"port\":8080,\"workers\":4,\"cors\":{\"enabled\":true,\"origins\":[\"http://localhost:3000\",\"https://myapp.com\"],\"methods\":[\"GET\",\"POST\",\"PUT\",\"DELETE\"],\"headers\":[\"Content-Type\",\"Authorization\"]}},\"logging\":{\"level\":\"info\",\"format\":\"json\",\"outputs\":[\"console\",\"file\"],\"file\":{\"path\":\"/var/log/myapp.log\",\"maxSize\":\"100MB\",\"rotate\":true}}}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

// ========== STREAMING DATA PATTERNS ==========

test "integration - streaming JSON processing" {
    const json_objects = [_][]const u8{
        "{\"event\":\"user_login\",\"user_id\":123,\"timestamp\":1701234567}",
        "{\"event\":\"page_view\",\"user_id\":123,\"page\":\"/dashboard\",\"timestamp\":1701234568}",
        "{\"event\":\"click\",\"user_id\":123,\"element\":\"button\",\"timestamp\":1701234569}",
        "{\"event\":\"user_logout\",\"user_id\":123,\"timestamp\":1701234570}",
    };

    for (json_objects) |input| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(input);
        try parser.flush();

        // Should produce same output since already minified
        try testing.expectEqualStrings(input, output.items);
    }
}

test "integration - line-delimited JSON" {
    const inputs = [_][]const u8{
        "{ \"name\": \"Alice\", \"age\": 30 }",
        "{ \"name\": \"Bob\", \"age\": 25 }",
        "{ \"name\": \"Charlie\", \"age\": 35 }",
    };

    const expected_outputs = [_][]const u8{
        "{\"name\":\"Alice\",\"age\":30}",
        "{\"name\":\"Bob\",\"age\":25}",
        "{\"name\":\"Charlie\",\"age\":35}",
    };

    for (inputs, expected_outputs) |input, expected| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(input);
        try parser.flush();

        try testing.expectEqualStrings(expected, output.items);
    }
}

// ========== MULTI-FORMAT COMPATIBILITY ==========

test "integration - GeoJSON compatibility" {
    const input =
        \\{
        \\  "type": "FeatureCollection",
        \\  "features": [
        \\    {
        \\      "type": "Feature",
        \\      "geometry": {
        \\        "type": "Point",
        \\        "coordinates": [-122.4194, 37.7749]
        \\      },
        \\      "properties": {
        \\        "name": "San Francisco",
        \\        "population": 883305
        \\      }
        \\    },
        \\    {
        \\      "type": "Feature",
        \\      "geometry": {
        \\        "type": "Polygon",
        \\        "coordinates": [[
        \\          [-122.4, 37.8],
        \\          [-122.4, 37.7],
        \\          [-122.3, 37.7],
        \\          [-122.3, 37.8],
        \\          [-122.4, 37.8]
        \\        ]]
        \\      },
        \\      "properties": {
        \\        "name": "Sample Area"
        \\      }
        \\    }
        \\  ]
        \\}
    ;

    const expected = "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[-122.4194,37.7749]},\"properties\":{\"name\":\"San Francisco\",\"population\":883305}},{\"type\":\"Feature\",\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[-122.4,37.8],[-122.4,37.7],[-122.3,37.7],[-122.3,37.8],[-122.4,37.8]]]},\"properties\":{\"name\":\"Sample Area\"}}]}";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input);
    try parser.flush();

    try testing.expectEqualStrings(expected, output.items);
}

test "integration - JSON-RPC compatibility" {
    const test_cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{
            .input =
            \\{
            \\  "jsonrpc": "2.0",
            \\  "method": "subtract",
            \\  "params": [42, 23],
            \\  "id": 1
            \\}
            ,
            .expected = "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,23],\"id\":1}",
        },
        .{
            .input =
            \\{
            \\  "jsonrpc": "2.0",
            \\  "result": 19,
            \\  "id": 1
            \\}
            ,
            .expected = "{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":1}",
        },
        .{
            .input =
            \\{
            \\  "jsonrpc": "2.0",
            \\  "error": {
            \\    "code": -32601,
            \\    "message": "Method not found"
            \\  },
            \\  "id": null
            \\}
            ,
            .expected = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32601,\"message\":\"Method not found\"},\"id\":null}",
        },
    };

    for (test_cases) |case| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(case.input);
        try parser.flush();

        try testing.expectEqualStrings(case.expected, output.items);
    }
}

// ========== STRESS AND RELIABILITY TESTS ==========

test "integration - mixed content stress test" {
    // Create a complex JSON with various data types and structures
    var input = std.ArrayList(u8).init(testing.allocator);
    defer input.deinit();

    try input.appendSlice("{ \"mixed_data\": [ ");

    // Add various data types
    const data_types = [_][]const u8{
        "null",
        "true",
        "false",
        "0",
        "-123",
        "3.14159",
        "1.23e-10",
        "\"simple string\"",
        "\"string with \\\"quotes\\\" and \\n newlines\"",
        "\"unicode: \\u00A9 \\u20AC \\uD83D\\uDE00\"",
        "{}",
        "[]",
        "{\"nested\": {\"deeply\": {\"nested\": \"value\"}}}",
        "[1, [2, [3, [4, 5]]]]",
    };

    for (data_types, 0..) |data, i| {
        if (i > 0) try input.appendSlice(", ");
        try input.appendSlice(data);
    }

    try input.appendSlice(" ] }");

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
    defer parser.deinit(testing.allocator);

    try parser.feed(input.items);
    try parser.flush();

    // Verify the output is valid and contains expected elements
    try testing.expect(output.items.len > 0);
    try testing.expect(std.mem.startsWith(u8, output.items, "{\"mixed_data\":["));
    try testing.expect(std.mem.endsWith(u8, output.items, "]}"));

    // Verify no unnecessary whitespace
    try testing.expect(std.mem.indexOf(u8, output.items, "  ") == null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\n") == null);
    try testing.expect(std.mem.indexOf(u8, output.items, "\t") == null);
}

test "integration - incremental processing reliability" {
    const full_json = "{\"large_array\":[" ++ "1," ** 999 ++ "1000]}";

    // Process the same JSON in different chunk sizes
    const chunk_sizes = [_]usize{ 1, 3, 7, 16, 64, 256 };

    var reference_output = std.ArrayList(u8).init(testing.allocator);
    defer reference_output.deinit();

    // Get reference output
    {
        var parser = try MinifyingParser.init(testing.allocator, reference_output.writer().any());
        defer parser.deinit(testing.allocator);
        try parser.feed(full_json);
        try parser.flush();
    }

    // Test each chunk size produces identical output
    for (chunk_sizes) |chunk_size| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        var pos: usize = 0;
        while (pos < full_json.len) {
            const end = @min(pos + chunk_size, full_json.len);
            try parser.feed(full_json[pos..end]);
            pos = end;
        }
        try parser.flush();

        try testing.expectEqualStrings(reference_output.items, output.items);
    }
}

// ========== CONSISTENCY AND IDEMPOTENCY ==========

test "integration - double minification idempotency" {
    const test_cases = [_][]const u8{
        "{ \"key\" : \"value\" }",
        "[ 1 , 2 , 3 ]",
        "{ \"nested\" : { \"object\" : [ 1 , 2 ] } }",
        "\"simple string\"",
        "12345",
        "true",
    };

    for (test_cases) |input| {
        // First minification
        var first_output = std.ArrayList(u8).init(testing.allocator);
        defer first_output.deinit();

        {
            var parser = try MinifyingParser.init(testing.allocator, first_output.writer().any());
            defer parser.deinit(testing.allocator);
            try parser.feed(input);
            try parser.flush();
        }

        // Second minification of the first result
        var second_output = std.ArrayList(u8).init(testing.allocator);
        defer second_output.deinit();

        {
            var parser = try MinifyingParser.init(testing.allocator, second_output.writer().any());
            defer parser.deinit(testing.allocator);
            try parser.feed(first_output.items);
            try parser.flush();
        }

        // Should be identical
        try testing.expectEqualStrings(first_output.items, second_output.items);
    }
}
