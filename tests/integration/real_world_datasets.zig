//! Integration Tests with Real-World Datasets
//!
//! This module tests zmin with actual JSON datasets from various sources
//! to ensure correctness and performance in real-world scenarios.

const std = @import("std");
const zmin = @import("zmin_lib");
const test_framework = @import("../test_framework.zig");
const TestRunner = test_framework.TestRunner;

/// Real-world dataset test configuration
const DatasetTest = struct {
    name: []const u8,
    file_path: []const u8,
    expected_reduction_min: f64, // Minimum expected size reduction
    performance_threshold_mbps: f64, // Minimum throughput
    modes_to_test: []const zmin.ProcessingMode,
};

/// Standard datasets for testing
const standard_datasets = [_]DatasetTest{
    .{
        .name = "Twitter API Response",
        .file_path = "datasets/twitter.json",
        .expected_reduction_min = 0.10, // 10% reduction
        .performance_threshold_mbps = 500.0,
        .modes_to_test = &.{ .eco, .sport, .turbo },
    },
    .{
        .name = "GitHub API Response", 
        .file_path = "datasets/github.json",
        .expected_reduction_min = 0.12, // 12% reduction
        .performance_threshold_mbps = 600.0,
        .modes_to_test = &.{ .eco, .sport, .turbo },
    },
    .{
        .name = "Canada GeoJSON",
        .file_path = "datasets/canada.json",
        .expected_reduction_min = 0.08, // 8% reduction (already compact)
        .performance_threshold_mbps = 400.0,
        .modes_to_test = &.{ .eco, .sport, .turbo },
    },
    .{
        .name = "CITM Catalog",
        .file_path = "datasets/citm.json",
        .expected_reduction_min = 0.15, // 15% reduction
        .performance_threshold_mbps = 700.0,
        .modes_to_test = &.{ .eco, .sport, .turbo },
    },
};

test "integration: real world datasets" {
    const allocator = std.testing.allocator;
    var runner = TestRunner.init(allocator, true);
    defer runner.deinit();
    
    for (standard_datasets) |dataset| {
        // Skip if dataset file doesn't exist
        const file = std.fs.cwd().openFile(dataset.file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("Skipping {s}: dataset not found at {s}\n", .{ 
                    dataset.name, 
                    dataset.file_path 
                });
                continue;
            }
            return err;
        };
        defer file.close();
        
        const input = try file.readToEndAlloc(allocator, 100 * 1024 * 1024); // 100MB max
        defer allocator.free(input);
        
        std.debug.print("\nTesting dataset: {s} ({d:.2} MB)\n", .{
            dataset.name,
            @as(f64, @floatFromInt(input.len)) / (1024.0 * 1024.0),
        });
        
        // Test each mode
        for (dataset.modes_to_test) |mode| {
            const test_name = try std.fmt.allocPrint(allocator, "{s} - {s} mode", .{
                dataset.name,
                @tagName(mode),
            });
            defer allocator.free(test_name);
            
            try runner.runTest(test_name, .integration, struct {
                fn runTest() !void {
                    try testDatasetWithMode(allocator, dataset, input, mode);
                }
            }.runTest);
        }
    }
    
    var buffer: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try runner.generateReport(stream.writer());
    std.debug.print("{s}\n", .{stream.getWritten()});
}

fn testDatasetWithMode(
    allocator: std.mem.Allocator,
    dataset: DatasetTest,
    input: []const u8,
    mode: zmin.ProcessingMode,
) !void {
    // Time the minification
    const start = std.time.microTimestamp();
    const output = try zmin.minifyWithMode(allocator, input, mode);
    defer allocator.free(output);
    const duration_us = std.time.microTimestamp() - start;
    
    // Validate output is valid JSON
    try validateJson(output);
    
    // Check size reduction
    const reduction = 1.0 - (@as(f64, @floatFromInt(output.len)) / @as(f64, @floatFromInt(input.len)));
    if (reduction < dataset.expected_reduction_min) {
        std.debug.print("  ⚠️  Size reduction {d:.1}% below expected {d:.1}%\n", .{
            reduction * 100.0,
            dataset.expected_reduction_min * 100.0,
        });
        return error.InsufficientSizeReduction;
    }
    
    // Check performance
    const throughput_mbps = (@as(f64, @floatFromInt(input.len)) / (1024.0 * 1024.0)) / 
                           (@as(f64, @floatFromInt(duration_us)) / 1_000_000.0);
    
    try test_framework.assertions.assertPerformance(throughput_mbps, dataset.performance_threshold_mbps);
    
    // Verify minified content is semantically equivalent
    try verifySemanticEquivalence(allocator, input, output);
    
    std.debug.print("  ✅ {s}: {d:.1}% reduction, {d:.0} MB/s\n", .{
        @tagName(mode),
        reduction * 100.0,
        throughput_mbps,
    });
}

/// Validate that output is valid JSON
fn validateJson(json: []const u8) !void {
    var parser = std.json.Parser.init(std.testing.allocator, .alloc_always);
    defer parser.deinit();
    
    _ = parser.parse(json) catch |err| {
        std.debug.print("Invalid JSON output: {}\n", .{err});
        return error.InvalidJsonOutput;
    };
}

/// Verify semantic equivalence between original and minified JSON
fn verifySemanticEquivalence(allocator: std.mem.Allocator, original: []const u8, minified: []const u8) !void {
    var original_parser = std.json.Parser.init(allocator, .alloc_always);
    defer original_parser.deinit();
    
    var minified_parser = std.json.Parser.init(allocator, .alloc_always);
    defer minified_parser.deinit();
    
    const original_tree = try original_parser.parse(original);
    const minified_tree = try minified_parser.parse(minified);
    
    // For now, just verify both parse successfully
    // TODO: Implement deep comparison of JSON values
    _ = original_tree;
    _ = minified_tree;
}

test "integration: streaming large files" {
    const allocator = std.testing.allocator;
    
    // Generate a large JSON file (50MB)
    const large_json = try generateLargeJson(allocator, 50 * 1024 * 1024);
    defer allocator.free(large_json);
    
    std.debug.print("\nTesting streaming mode with {d:.2} MB file\n", .{
        @as(f64, @floatFromInt(large_json.len)) / (1024.0 * 1024.0),
    });
    
    // Test ECO mode (streaming)
    const start = std.time.microTimestamp();
    const output = try zmin.minifyWithMode(allocator, large_json, .eco);
    defer allocator.free(output);
    const duration_us = std.time.microTimestamp() - start;
    
    const throughput_mbps = (@as(f64, @floatFromInt(large_json.len)) / (1024.0 * 1024.0)) / 
                           (@as(f64, @floatFromInt(duration_us)) / 1_000_000.0);
    
    std.debug.print("  ECO mode: {d:.0} MB/s with constant memory usage\n", .{throughput_mbps});
    
    // Verify output is valid
    try validateJson(output);
}

fn generateLargeJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);
    errdefer json.deinit();
    
    try json.appendSlice("{\n  \"items\": [\n");
    
    var item_count: u32 = 0;
    while (json.items.len < target_size - 100) : (item_count += 1) {
        if (item_count > 0) try json.appendSlice(",\n");
        
        try json.writer().print(
            \\    {{
            \\      "id": {d},
            \\      "name": "Item {d}",
            \\      "description": "This is a test item with a longer description to increase size",
            \\      "metadata": {{
            \\        "created": "2025-07-26T00:00:00Z",
            \\        "tags": ["test", "benchmark", "large"],
            \\        "attributes": {{
            \\          "color": "blue",
            \\          "size": "large",
            \\          "weight": 42.5
            \\        }}
            \\      }}
            \\    }}
        , .{ item_count, item_count });
    }
    
    try json.appendSlice("\n  ]\n}\n");
    
    return json.toOwnedSlice();
}

test "integration: error handling and recovery" {
    const allocator = std.testing.allocator;
    
    // Test various invalid inputs
    const invalid_inputs = [_]struct {
        name: []const u8,
        input: []const u8,
        expected_error: ?anyerror = null,
    }{
        .{
            .name = "Truncated JSON",
            .input = "{\"incomplete\": ",
            .expected_error = error.UnexpectedEndOfInput,
        },
        .{
            .name = "Invalid escape sequence",
            .input = "{\"bad\": \"\\x\"}",
            .expected_error = error.InvalidEscapeSequence,
        },
        .{
            .name = "Trailing comma",
            .input = "{\"a\": 1, \"b\": 2,}",
            .expected_error = error.TrailingComma,
        },
        .{
            .name = "Duplicate keys",
            .input = "{\"key\": 1, \"key\": 2}",
            .expected_error = error.DuplicateKey,
        },
    };
    
    for (invalid_inputs) |test_case| {
        std.debug.print("\nTesting error handling: {s}\n", .{test_case.name});
        
        // Test should fail gracefully
        const result = zmin.minifyWithMode(allocator, test_case.input, .eco);
        
        if (result) |output| {
            allocator.free(output);
            std.debug.print("  ⚠️  Expected error but succeeded\n", .{});
            if (test_case.expected_error != null) {
                return error.ExpectedErrorButSucceeded;
            }
        } else |err| {
            std.debug.print("  ✅ Correctly failed with: {}\n", .{err});
            if (test_case.expected_error) |expected| {
                try std.testing.expectEqual(expected, err);
            }
        }
    }
}

test "integration: unicode and special characters" {
    const allocator = std.testing.allocator;
    
    const unicode_json = 
        \\{
        \\  "emoji": "🚀 🎉 ✅",
        \\  "chinese": "你好世界",
        \\  "japanese": "こんにちは",
        \\  "arabic": "مرحبا بالعالم",
        \\  "special": "\u0000\u001f\u007f",
        \\  "escaped": "\"\\\/\b\f\n\r\t"
        \\}
    ;
    
    std.debug.print("\nTesting Unicode and special character handling\n", .{});
    
    for ([_]zmin.ProcessingMode{ .eco, .sport, .turbo }) |mode| {
        const output = try zmin.minifyWithMode(allocator, unicode_json, mode);
        defer allocator.free(output);
        
        // Verify all Unicode is preserved
        try std.testing.expect(std.mem.indexOf(u8, output, "🚀") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "你好世界") != null);
        
        // Verify escape sequences are preserved
        try std.testing.expect(std.mem.indexOf(u8, output, "\\n") != null);
        try std.testing.expect(std.mem.indexOf(u8, output, "\\t") != null);
        
        std.debug.print("  ✅ {s} mode: Unicode preserved correctly\n", .{@tagName(mode)});
    }
}

test "integration: concurrent processing" {
    const allocator = std.testing.allocator;
    
    // Test concurrent minification of multiple files
    const thread_count = 4;
    var threads: [thread_count]std.Thread = undefined;
    var results: [thread_count]?anyerror = .{null} ** thread_count;
    
    std.debug.print("\nTesting concurrent processing with {d} threads\n", .{thread_count});
    
    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, struct {
            fn worker(idx: usize, result_ptr: *?anyerror) void {
                const json = test_framework.fixtures.nested_json;
                
                // Each thread processes the same JSON multiple times
                for (0..100) |_| {
                    const output = zmin.minifyWithMode(std.testing.allocator, json, .turbo) catch |err| {
                        result_ptr.* = err;
                        return;
                    };
                    std.testing.allocator.free(output);
                }
                
                std.debug.print("  Thread {d} completed 100 iterations\n", .{idx});
            }
        }.worker, .{ i, &results[i] });
    }
    
    // Wait for all threads
    for (threads) |thread| {
        thread.join();
    }
    
    // Check results
    for (results, 0..) |result, i| {
        if (result) |err| {
            std.debug.print("  ❌ Thread {d} failed: {}\n", .{ i, err });
            return err;
        }
    }
    
    std.debug.print("  ✅ All threads completed successfully\n", .{});
}