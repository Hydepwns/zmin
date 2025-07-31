const std = @import("std");
const testing = std.testing;
const test_framework = @import("../helpers/test_framework.zig");
const TestRunner = test_framework.TestRunner;
const TestCategory = test_framework.TestCategory;
const errors = @import("../../tools/common/errors.zig");

/// Mock network components for testing
const MockConnection = struct {
    data: []const u8,
    written_data: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, response_data: []const u8) Self {
        return Self{
            .data = response_data,
            .written_data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.written_data.deinit();
    }

    pub const Stream = struct {
        connection: *MockConnection,

        pub fn reader(self: Stream) MockReader {
            return MockReader{ .connection = self.connection };
        }

        pub fn writer(self: Stream) MockWriter {
            return MockWriter{ .connection = self.connection };
        }

        pub fn close(_: Stream) void {
            // No-op for mock
        }
    };

    pub const MockReader = struct {
        connection: *MockConnection,
        read_pos: usize = 0,

        pub fn read(self: *MockReader, buffer: []u8) !usize {
            const remaining = self.connection.data.len - self.read_pos;
            const to_read = @min(buffer.len, remaining);

            @memcpy(buffer[0..to_read], self.connection.data[self.read_pos .. self.read_pos + to_read]);
            self.read_pos += to_read;

            return to_read;
        }
    };

    pub const MockWriter = struct {
        connection: *MockConnection,

        pub fn writeAll(self: MockWriter, data: []const u8) !void {
            try self.connection.written_data.appendSlice(data);
        }
    };

    pub fn getStream(self: *Self) Stream {
        return Stream{ .connection = self };
    }
};

/// Run all dev_server unit tests
pub fn runAllTests(allocator: std.mem.Allocator, verbose: bool) !void {
    var runner = TestRunner.init(allocator, verbose);
    defer runner.deinit();

    // Dev server specific tests
    try runner.runTest("DevServer error handling", .unit, testDevServerErrorHandling);
    try runner.runTest("DevServer HTTP parsing", .unit, testDevServerHttpParsing);
    try runner.runTest("DevServer JSON response", .unit, testDevServerJsonResponse);
    try runner.runTest("DevServer file operations", .unit, testDevServerFileOperations);

    // Generate and print test report
    const stdout = std.io.getStdOut().writer();
    try runner.generateReport(stdout);
}

/// Test dev_server error handling integration
fn testDevServerErrorHandling() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test ErrorReporter initialization
    var reporter = errors.ErrorReporter.init(allocator, "dev-server");
    try testing.expectEqualStrings("dev-server", reporter.tool_name);

    // Test FileOps integration
    const file_ops = errors.FileOps{ .reporter = &reporter };

    // Test reading non-existent file
    const result = file_ops.readFile(allocator, "/nonexistent/path.txt");
    try testing.expectError(errors.DevToolError.FileNotFound, result);

    // Test ProcessOps integration
    const process_ops = errors.ProcessOps{ .reporter = &reporter };
    _ = process_ops; // Available for use
}

/// Test HTTP request parsing functionality
fn testDevServerHttpParsing() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test valid HTTP request parsing
    const valid_request =
        \\GET /api/minify HTTP/1.1
        \\Host: localhost:8080
        \\Content-Type: application/json
        \\Content-Length: 43
        \\
        \\{"input": "{\"test\": true}", "mode": "sport"}
    ;

    // Parse request line
    var lines = std.mem.splitSequence(u8, valid_request, "\r\n");
    const request_line = lines.next();
    try testing.expect(request_line != null);

    var parts = std.mem.splitSequence(u8, request_line.?, " ");
    const method = parts.next();
    const path = parts.next();

    try testing.expect(method != null);
    try testing.expect(path != null);
    try testing.expectEqualStrings("GET", method.?);
    try testing.expectEqualStrings("/api/minify", path.?);

    // Test body extraction
    const body_start = std.mem.indexOf(u8, valid_request, "\r\n\r\n");
    try testing.expect(body_start != null);

    const body = valid_request[body_start.? + 4 ..];
    try testing.expect(std.mem.indexOf(u8, body, "input") != null);
    try testing.expect(std.mem.indexOf(u8, body, "mode") != null);
}

/// Test JSON response formatting
fn testDevServerJsonResponse() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test JSON response creation
    const test_data = .{
        .output = "{\"test\":true}",
        .original_size = 15,
        .minified_size = 13,
        .compression_ratio = 0.87,
    };

    const response_json = try std.fmt.allocPrint(allocator,
        \\{{"output":"{s}","original_size":{d},"minified_size":{d},"compression_ratio":{d:.2}}}
    , .{
        test_data.output,
        test_data.original_size,
        test_data.minified_size,
        test_data.compression_ratio,
    });
    defer allocator.free(response_json);

    // Validate JSON structure
    try testing.expect(std.mem.indexOf(u8, response_json, "output") != null);
    try testing.expect(std.mem.indexOf(u8, response_json, "original_size") != null);
    try testing.expect(std.mem.indexOf(u8, response_json, "minified_size") != null);
    try testing.expect(std.mem.indexOf(u8, response_json, "compression_ratio") != null);

    // Test HTTP response formatting
    const http_response = try std.fmt.allocPrint(allocator,
        \\HTTP/1.1 200 OK
        \\Content-Type: application/json
        \\Access-Control-Allow-Origin: *
        \\Content-Length: {d}
        \\
        \\
    , .{response_json.len});
    defer allocator.free(http_response);

    try testing.expect(std.mem.indexOf(u8, http_response, "200 OK") != null);
    try testing.expect(std.mem.indexOf(u8, http_response, "application/json") != null);
    try testing.expect(std.mem.indexOf(u8, http_response, "Access-Control-Allow-Origin") != null);
}

/// Test dev_server file operations
fn testDevServerFileOperations() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var reporter = errors.ErrorReporter.init(allocator, "dev-server");
    const file_ops = errors.FileOps{ .reporter = &reporter };

    // Test embedded file access (simulated)
    const embedded_content = @embedFile("../fixtures/simple.json");
    try testing.expect(embedded_content.len > 0);
    try testing.expect(std.mem.indexOf(u8, embedded_content, "name") != null);

    // Test file operations error handling
    const read_result = file_ops.readFile(allocator, "/tmp/nonexistent_test_file.json");
    try testing.expectError(errors.DevToolError.FileNotFound, read_result);
}

/// Test system information detection functions
fn testSystemInfoDetection() !void {
    // Test memory detection (should not crash)
    const total_memory = @import("../../tools/dev_server.zig").getTotalMemory();
    try testing.expect(total_memory > 0);

    const current_memory = @import("../../tools/dev_server.zig").getCurrentMemoryUsage();
    // Current memory can be 0 on some systems, so just ensure it doesn't crash
    _ = current_memory;
}

/// Main test entry point for this module
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try runAllTests(allocator, true);
}
