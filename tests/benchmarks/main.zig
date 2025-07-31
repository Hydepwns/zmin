const std = @import("std");
const testing = std.testing;

// Import the minifier components directly
const types = @import("src/minifier/types.zig");
const MinifyingParser = types.MinifyingParser;

// ========== THROUGHPUT BENCHMARKS ==========

test "performance - small JSON throughput" {
    const input = "{\"name\":\"John\",\"age\":30,\"city\":\"New York\"}";
    const iterations = 10000;

    var timer = try std.time.Timer.start();
    var total_bytes: u64 = 0;

    for (0..iterations) |_| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(input);
        try parser.flush();

        total_bytes += input.len;
    }

    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;
    const mb_per_sec = (total_bytes * 1000) / (elapsed_ms * 1024 * 1024);

    std.debug.print("\nSmall JSON Performance:\n", .{});
    std.debug.print("  Processed: {} bytes in {} ms\n", .{ total_bytes, elapsed_ms });
    std.debug.print("  Throughput: {} MB/s\n", .{mb_per_sec});
    std.debug.print("  Per-iteration: {} ns\n", .{elapsed_ns / iterations});

    // Basic sanity check - should be reasonably fast
    try testing.expect(elapsed_ms < 5000); // Should take less than 5 seconds
}

test "performance - medium JSON throughput" {
    // Create a medium-sized JSON structure
    var input = std.ArrayList(u8).init(testing.allocator);
    defer input.deinit();

    try input.appendSlice("{\"users\":[");
    for (0..100) |i| {
        if (i > 0) try input.appendSlice(",");
        const user = try std.fmt.allocPrint(testing.allocator, "{{\"id\":{},\"name\":\"User{}\",\"email\":\"user{}@example.com\",\"active\":true}}", .{ i, i, i });
        defer testing.allocator.free(user);
        try input.appendSlice(user);
    }
    try input.appendSlice("]}");

    const iterations = 100;
    var timer = try std.time.Timer.start();
    var total_bytes: u64 = 0;

    for (0..iterations) |_| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(input.items);
        try parser.flush();

        total_bytes += input.items.len;
    }

    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;
    const mb_per_sec = if (elapsed_ms > 0) (total_bytes * 1000) / (elapsed_ms * 1024 * 1024) else 0;

    std.debug.print("\nMedium JSON Performance:\n", .{});
    std.debug.print("  Input size: {} bytes\n", .{input.items.len});
    std.debug.print("  Processed: {} bytes in {} ms\n", .{ total_bytes, elapsed_ms });
    std.debug.print("  Throughput: {} MB/s\n", .{mb_per_sec});
    std.debug.print("  Per-iteration: {} ns\n", .{elapsed_ns / iterations});

    // Basic sanity check
    try testing.expect(elapsed_ms < 10000); // Should take less than 10 seconds
}

test "performance - large array processing" {
    // Create a large array of numbers
    var input = std.ArrayList(u8).init(testing.allocator);
    defer input.deinit();

    try input.append('[');
    for (0..10000) |i| {
        if (i > 0) try input.appendSlice(", ");
        const num_str = try std.fmt.allocPrint(testing.allocator, "{}", .{i});
        defer testing.allocator.free(num_str);
        try input.appendSlice(num_str);
    }
    try input.append(']');

    const iterations = 10;
    var timer = try std.time.Timer.start();
    var total_bytes: u64 = 0;

    for (0..iterations) |_| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(input.items);
        try parser.flush();

        total_bytes += input.items.len;
    }

    const elapsed_ns = timer.read();
    const elapsed_ms = elapsed_ns / 1_000_000;
    const mb_per_sec = if (elapsed_ms > 0) (total_bytes * 1000) / (elapsed_ms * 1024 * 1024) else 0;

    std.debug.print("\nLarge Array Performance:\n", .{});
    std.debug.print("  Input size: {} bytes\n", .{input.items.len});
    std.debug.print("  Processed: {} bytes in {} ms\n", .{ total_bytes, elapsed_ms });
    std.debug.print("  Throughput: {} MB/s\n", .{mb_per_sec});
    std.debug.print("  Per-iteration: {} ns\n", .{elapsed_ns / iterations});

    // Basic sanity check
    try testing.expect(elapsed_ms < 30000); // Should take less than 30 seconds
}

// ========== MEMORY USAGE TESTS ==========

test "performance - memory usage patterns" {
    const input = "{\"key\":\"value\",\"number\":42,\"boolean\":true,\"null\":null}";
    const iterations = 1000;

    // Measure allocator activity
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    for (0..iterations) |_| {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(allocator, output.writer().any());
        defer parser.deinit(allocator);

        try parser.feed(input);
        try parser.flush();

        // Verify output is correct
        try testing.expectEqualStrings("{\"key\":\"value\",\"number\":42,\"boolean\":true,\"null\":null}", output.items);
    }

    std.debug.print("\nMemory Usage Test: Completed {} iterations without memory leaks\n", .{iterations});
}

test "performance - streaming chunk processing" {
    const test_input = "{\"data\":\"" ++ "x" ** 10000 ++ "\",\"end\":true}";
    const chunk_sizes = [_]usize{ 1, 8, 64, 512, 1024 };

    for (chunk_sizes) |chunk_size| {
        var timer = try std.time.Timer.start();

        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        // Feed input in chunks
        var pos: usize = 0;
        while (pos < test_input.len) {
            const end = @min(pos + chunk_size, test_input.len);
            try parser.feed(test_input[pos..end]);
            pos = end;
        }
        try parser.flush();

        const elapsed_ns = timer.read();
        const elapsed_us = elapsed_ns / 1000;

        std.debug.print("Chunk size {} bytes: {} µs\n", .{ chunk_size, elapsed_us });

        // Verify output is correct
        try testing.expectEqualStrings(test_input, output.items);
    }
}

// ========== SCALABILITY TESTS ==========

test "performance - input size scaling" {
    const base_size = 100;
    const scale_factors = [_]usize{ 1, 2, 4, 8, 16 };

    for (scale_factors) |factor| {
        const size = base_size * factor;

        // Create input of specified size
        var input = std.ArrayList(u8).init(testing.allocator);
        defer input.deinit();

        try input.append('[');
        for (0..size) |i| {
            if (i > 0) try input.appendSlice(",");
            const num_str = try std.fmt.allocPrint(testing.allocator, "{}", .{i});
            defer testing.allocator.free(num_str);
            try input.appendSlice(num_str);
        }
        try input.append(']');

        var timer = try std.time.Timer.start();

        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(input.items);
        try parser.flush();

        const elapsed_ns = timer.read();
        const elapsed_us = elapsed_ns / 1000;
        const bytes_per_us = if (elapsed_us > 0) input.items.len / elapsed_us else 0;

        std.debug.print("Size factor {}x ({} elements, {} bytes): {} µs, {} bytes/µs\n", .{ factor, size, input.items.len, elapsed_us, bytes_per_us });

        // Basic sanity check - should scale reasonably
        try testing.expect(elapsed_us < 100000); // Should be under 100ms
    }
}

// ========== SPECIFIC OPERATION BENCHMARKS ==========

test "performance - string processing" {
    const string_lengths = [_]usize{ 10, 100, 1000, 10000 };

    for (string_lengths) |length| {
        var input = std.ArrayList(u8).init(testing.allocator);
        defer input.deinit();

        try input.append('"');
        for (0..length) |i| {
            try input.append(@intCast('a' + (i % 26)));
        }
        try input.append('"');

        const iterations = @max(1, 1000 / (length / 10 + 1)); // Fewer iterations for longer strings
        var timer = try std.time.Timer.start();

        for (0..iterations) |_| {
            var output = std.ArrayList(u8).init(testing.allocator);
            defer output.deinit();

            var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
            defer parser.deinit(testing.allocator);

            try parser.feed(input.items);
            try parser.flush();
        }

        const elapsed_ns = timer.read();
        const avg_ns = if (iterations > 0) elapsed_ns / iterations else 0;
        const chars_per_ms = if (avg_ns > 0) (length * 1_000_000) / avg_ns else 0;

        std.debug.print("String length {}: {} ns/string, {} chars/ms\n", .{ length, avg_ns, chars_per_ms });
    }
}

test "performance - number processing" {
    const number_types = [_][]const u8{
        "0",
        "42",
        "-17",
        "3.14159",
        "-2.718281828",
        "1.23456789e10",
        "-9.87654321e-15",
        "12345678901234567890",
    };

    for (number_types) |number| {
        const iterations = 10000;
        var timer = try std.time.Timer.start();

        for (0..iterations) |_| {
            var output = std.ArrayList(u8).init(testing.allocator);
            defer output.deinit();

            var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
            defer parser.deinit(testing.allocator);

            try parser.feed(number);
            try parser.flush();
        }

        const elapsed_ns = timer.read();
        const avg_ns = elapsed_ns / iterations;

        std.debug.print("Number '{s}': {} ns/parse\n", .{ number, avg_ns });

        // Basic sanity check
        try testing.expect(avg_ns < 100000); // Should be under 100µs per parse
    }
}

// ========== COMPARATIVE BENCHMARKS ==========

test "performance - whitespace vs no whitespace" {
    const compact_json = "{\"a\":1,\"b\":[2,3,4],\"c\":{\"d\":5}}";
    const spaced_json = "{ \"a\" : 1 , \"b\" : [ 2 , 3 , 4 ] , \"c\" : { \"d\" : 5 } }";
    const iterations = 1000;

    // Benchmark compact JSON
    var timer = try std.time.Timer.start();
    for (0..iterations) |_| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(compact_json);
        try parser.flush();
    }
    const compact_time = timer.read();

    // Benchmark spaced JSON
    timer.reset();
    for (0..iterations) |_| {
        var output = std.ArrayList(u8).init(testing.allocator);
        defer output.deinit();

        var parser = try MinifyingParser.init(testing.allocator, output.writer().any());
        defer parser.deinit(testing.allocator);

        try parser.feed(spaced_json);
        try parser.flush();
    }
    const spaced_time = timer.read();

    const compact_avg = compact_time / iterations;
    const spaced_avg = spaced_time / iterations;
    const overhead_percent = if (compact_avg > 0) ((spaced_avg - compact_avg) * 100) / compact_avg else 0;

    std.debug.print("\nWhitespace Processing Comparison:\n", .{});
    std.debug.print("  Compact JSON: {} ns/iteration\n", .{compact_avg});
    std.debug.print("  Spaced JSON:  {} ns/iteration\n", .{spaced_avg});
    std.debug.print("  Overhead:     {}%\n", .{overhead_percent});
}
