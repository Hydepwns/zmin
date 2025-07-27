//! Streaming example for zmin
//!
//! This example demonstrates how to process large JSON files using streaming
//! to minimize memory usage.

const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage(args[0]);
        return;
    }

    const input_path = args[1];
    const output_path = if (args.len > 2) args[2] else "output.json";

    // Example 1: Basic streaming
    try example1_basic_streaming(allocator, input_path, output_path);

    // Example 2: Chunked processing
    try example2_chunked_processing(allocator, input_path);

    // Example 3: Pipeline streaming
    try example3_pipeline_streaming(allocator);
}

fn printUsage(program_name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Usage: {s} <input.json> [output.json]\n", .{program_name});
    try stdout.print("\nThis example demonstrates streaming JSON minification.\n", .{});
}

fn example1_basic_streaming(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: []const u8,
) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n=== Example 1: Basic Streaming ===\n", .{});

    // Open input file
    const input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();

    // Create output file
    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    // Create streaming minifier
    var minifier = zmin.StreamingMinifier.init(allocator);
    defer minifier.deinit();

    // Process in chunks
    const chunk_size = 4096;
    var buffer: [chunk_size]u8 = undefined;
    var total_input: usize = 0;
    var total_output: usize = 0;

    const start = std.time.milliTimestamp();

    while (true) {
        const bytes_read = try input_file.read(&buffer);
        if (bytes_read == 0) break;

        total_input += bytes_read;

        // Process chunk
        try minifier.process(buffer[0..bytes_read]);

        // Write any available output
        while (minifier.hasOutput()) {
            const output = minifier.getOutput();
            try output_file.writeAll(output);
            total_output += output.len;
        }
    }

    // Finish processing
    try minifier.finish();
    while (minifier.hasOutput()) {
        const output = minifier.getOutput();
        try output_file.writeAll(output);
        total_output += output.len;
    }

    const duration = std.time.milliTimestamp() - start;

    try stdout.print("Processed {d} bytes → {d} bytes in {d} ms\n", .{
        total_input,
        total_output,
        duration,
    });

    const compression = @as(f32, @floatFromInt(total_input - total_output)) /
        @as(f32, @floatFromInt(total_input)) * 100;
    try stdout.print("Compression: {d:.1}%\n", .{compression});
}

fn example2_chunked_processing(
    allocator: std.mem.Allocator,
    input_path: []const u8,
) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n=== Example 2: Chunked Processing ===\n", .{});
    try stdout.print("Processing file in memory-efficient chunks...\n", .{});

    // Open file
    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const chunk_size = 64 * 1024; // 64KB chunks

    var offset: usize = 0;
    var chunk_count: u32 = 0;

    while (offset < file_size) {
        // Calculate chunk boundaries
        const start_pos = offset;
        var end_pos = @min(offset + chunk_size, file_size);

        // Adjust end position to avoid splitting JSON tokens
        if (end_pos < file_size) {
            try file.seekTo(end_pos);
            var check_buf: [1024]u8 = undefined;
            const check_len = try file.read(&check_buf);

            // Find a safe split point (after whitespace or structural character)
            var split_offset: usize = 0;
            for (check_buf[0..check_len]) |c| {
                if (c == ' ' or c == '\n' or c == '\t' or
                    c == ',' or c == '}' or c == ']')
                {
                    break;
                }
                split_offset += 1;
            }

            end_pos += split_offset;
        }

        // Read and process chunk
        const chunk_len = end_pos - start_pos;
        try file.seekTo(start_pos);

        const chunk = try allocator.alloc(u8, chunk_len);
        defer allocator.free(chunk);

        _ = try file.read(chunk);

        chunk_count += 1;
        try stdout.print("  Chunk {d}: {d} bytes at offset {d}\n", .{
            chunk_count,
            chunk_len,
            start_pos,
        });

        offset = end_pos;
    }

    try stdout.print("Processed {d} chunks\n", .{chunk_count});
}

fn example3_pipeline_streaming(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n=== Example 3: Pipeline Streaming ===\n", .{});
    try stdout.print("Demonstrating producer-consumer pipeline...\n\n", .{});

    // Create a pipe for communication
    const pipe = try std.os.pipe();
    defer {
        std.os.close(pipe[0]);
        std.os.close(pipe[1]);
    }

    // Producer thread - generates JSON
    const producer_thread = try std.Thread.spawn(.{}, producer, .{ pipe[1], allocator });

    // Consumer thread - minifies JSON
    const consumer_thread = try std.Thread.spawn(.{}, consumer, .{ pipe[0], allocator });

    // Wait for completion
    producer_thread.join();
    consumer_thread.join();

    try stdout.print("Pipeline processing complete!\n", .{});
}

fn producer(write_fd: std.os.fd_t, _: std.mem.Allocator) !void {
    const file = std.fs.File{ .handle = write_fd };
    const writer = file.writer();

    // Generate JSON data in chunks
    try writer.writeAll("{\n  \"records\": [\n");

    for (0..1000) |i| {
        if (i > 0) try writer.writeAll(",\n");

        try writer.print(
            \\    {{
            \\      "id": {d},
            \\      "timestamp": {d},
            \\      "data": "Record {d}"
            \\    }}
        , .{ i, std.time.timestamp(), i });

        // Simulate real-time data generation
        std.time.sleep(1000000); // 1ms
    }

    try writer.writeAll("\n  ]\n}");

    // Close write end to signal EOF
    std.os.close(write_fd);
}

fn consumer(read_fd: std.os.fd_t, allocator: std.mem.Allocator) !void {
    const file = std.fs.File{ .handle = read_fd };
    const reader = file.reader();

    var minifier = zmin.StreamingMinifier.init(allocator);
    defer minifier.deinit();

    var buffer: [1024]u8 = undefined;
    var total_output: usize = 0;

    while (true) {
        const bytes_read = try reader.read(&buffer);
        if (bytes_read == 0) break;

        try minifier.process(buffer[0..bytes_read]);

        while (minifier.hasOutput()) {
            const output = minifier.getOutput();
            total_output += output.len;
            // In real use, write to file or send over network
        }
    }

    try minifier.finish();
    while (minifier.hasOutput()) {
        const output = minifier.getOutput();
        total_output += output.len;
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Consumer processed {d} bytes of minified output\n", .{total_output});
}
