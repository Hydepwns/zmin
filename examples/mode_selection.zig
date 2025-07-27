//! Mode selection example for zmin
//!
//! This example demonstrates how to choose and use different processing modes
//! based on your requirements.

const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    try stdout.print("=== zmin Mode Selection Example ===\n\n", .{});

    // Generate test data of different sizes
    const small_json = try generateJson(allocator, 100); // ~3KB
    defer allocator.free(small_json);

    const medium_json = try generateJson(allocator, 1000); // ~30KB
    defer allocator.free(medium_json);

    const large_json = try generateJson(allocator, 10000); // ~300KB
    defer allocator.free(large_json);

    // Test all modes with different data sizes
    try stdout.print("Testing different modes with various data sizes:\n\n", .{});

    try testMode(allocator, "Small JSON (3KB)", small_json, .eco);
    try testMode(allocator, "Small JSON (3KB)", small_json, .sport);
    try testMode(allocator, "Small JSON (3KB)", small_json, .turbo);

    try stdout.print("\n", .{});

    try testMode(allocator, "Medium JSON (30KB)", medium_json, .eco);
    try testMode(allocator, "Medium JSON (30KB)", medium_json, .sport);
    try testMode(allocator, "Medium JSON (30KB)", medium_json, .turbo);

    try stdout.print("\n", .{});

    try testMode(allocator, "Large JSON (300KB)", large_json, .eco);
    try testMode(allocator, "Large JSON (300KB)", large_json, .sport);
    try testMode(allocator, "Large JSON (300KB)", large_json, .turbo);

    // Mode selection guide
    try stdout.print("\n=== Mode Selection Guide ===\n\n", .{});
    try stdout.print("ECO Mode:\n", .{});
    try stdout.print("  - Memory usage: 64KB limit\n", .{});
    try stdout.print("  - Best for: Embedded systems, IoT devices\n", .{});
    try stdout.print("  - Use when: Memory is extremely limited\n\n", .{});

    try stdout.print("SPORT Mode (Default):\n", .{});
    try stdout.print("  - Memory usage: Balanced\n", .{});
    try stdout.print("  - Best for: General purpose, web servers\n", .{});
    try stdout.print("  - Use when: You need good performance with reasonable memory\n\n", .{});

    try stdout.print("TURBO Mode:\n", .{});
    try stdout.print("  - Memory usage: Unrestricted\n", .{});
    try stdout.print("  - Best for: Large files, batch processing\n", .{});
    try stdout.print("  - Use when: Speed is critical and memory is plentiful\n\n", .{});

    // Demonstrate automatic mode selection
    try demonstrateAutoModeSelection(allocator);
}

fn testMode(
    allocator: std.mem.Allocator,
    description: []const u8,
    json: []const u8,
    mode: zmin.ProcessingMode,
) !void {
    const stdout = std.io.getStdOut().writer();

    // Run multiple iterations for accurate timing
    const iterations: u32 = 100;
    var total_time: u64 = 0;
    var output_size: usize = 0;

    for (0..iterations) |_| {
        const start = std.time.microTimestamp();
        const output = try zmin.minifyWithMode(allocator, json, mode);
        const duration = std.time.microTimestamp() - start;

        output_size = output.len;
        allocator.free(output);
        total_time += duration;
    }

    const avg_time = total_time / iterations;
    const throughput = @as(f32, @floatFromInt(json.len)) / @as(f32, @floatFromInt(avg_time)) * 1000;

    try stdout.print("{s} - {s: <6} mode: {d: >6} µs, {d: >6.0} KB/s\n", .{
        description,
        @tagName(mode),
        avg_time,
        throughput,
    });
}

fn generateJson(allocator: std.mem.Allocator, items: u32) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);
    var writer = json.writer();

    try writer.writeAll("{\n  \"users\": [\n");

    for (0..items) |i| {
        if (i > 0) try writer.writeAll(",\n");

        try writer.print(
            \\    {{
            \\      "id": {d},
            \\      "name": "User {d}",
            \\      "email": "user{d}@example.com",
            \\      "active": {s},
            \\      "score": {d:.2}
            \\    }}
        , .{
            i,
            i,
            i,
            if (i % 2 == 0) "true" else "false",
            @as(f32, @floatFromInt(i)) * 1.5,
        });
    }

    try writer.writeAll("\n  ]\n}");

    return json.toOwnedSlice();
}

fn demonstrateAutoModeSelection(_: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("=== Automatic Mode Selection ===\n\n", .{});
    try stdout.print("Here's how to automatically select the best mode:\n\n", .{});

    // Example implementation
    const code_example =
        \\fn selectBestMode(input_size: usize, available_memory: usize) zmin.ProcessingMode {
        \\    // For very small inputs, ECO is often fastest due to cache efficiency
        \\    if (input_size < 1024) {
        \\        return .eco;
        \\    }
        \\    
        \\    // If memory is constrained, use ECO
        \\    if (available_memory < 1024 * 1024) { // < 1MB
        \\        return .eco;
        \\    }
        \\    
        \\    // For large files with plenty of memory, use TURBO
        \\    if (input_size > 10 * 1024 * 1024 and available_memory > 100 * 1024 * 1024) {
        \\        return .turbo;
        \\    }
        \\    
        \\    // Default to SPORT for balanced performance
        \\    return .sport;
        \\}
    ;

    try stdout.print("{s}\n\n", .{code_example});

    // Demonstrate the function
    const test_cases = [_]struct {
        input_size: usize,
        available_mem: usize,
    }{
        .{ .input_size = 500, .available_mem = 64 * 1024 },
        .{ .input_size = 50 * 1024, .available_mem = 512 * 1024 },
        .{ .input_size = 50 * 1024 * 1024, .available_mem = 1024 * 1024 * 1024 },
    };

    try stdout.print("Example selections:\n", .{});
    for (test_cases) |tc| {
        const mode = selectBestMode(tc.input_size, tc.available_mem);
        try stdout.print("  Input: {d: >8} bytes, Memory: {d: >10} bytes → {s} mode\n", .{
            tc.input_size,
            tc.available_mem,
            @tagName(mode),
        });
    }
}

fn selectBestMode(input_size: usize, available_memory: usize) zmin.ProcessingMode {
    // For very small inputs, ECO is often fastest due to cache efficiency
    if (input_size < 1024) {
        return .eco;
    }

    // If memory is constrained, use ECO
    if (available_memory < 1024 * 1024) { // < 1MB
        return .eco;
    }

    // For large files with plenty of memory, use TURBO
    if (input_size > 10 * 1024 * 1024 and available_memory > 100 * 1024 * 1024) {
        return .turbo;
    }

    // Default to SPORT for balanced performance
    return .sport;
}
