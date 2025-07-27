// Simple test for parallel implementation
const std = @import("std");

// Copy the simple parallel implementation inline
const TurboMinifierParallelSimple = struct {
    allocator: std.mem.Allocator,
    thread_count: usize,

    pub const Config = struct {
        thread_count: usize = 0, // 0 = auto
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !TurboMinifierParallelSimple {
        const thread_count = if (config.thread_count == 0)
            try std.Thread.getCpuCount()
        else
            config.thread_count;

        return TurboMinifierParallelSimple{
            .allocator = allocator,
            .thread_count = thread_count,
        };
    }

    pub fn deinit(self: *TurboMinifierParallelSimple) void {
        _ = self;
    }

    pub fn minify(self: *TurboMinifierParallelSimple, input: []const u8, output: []u8) !usize {
        // For small inputs, use single thread
        if (input.len < 1024 * 1024 or self.thread_count == 1) {
            return minifyChunk(input, output);
        }

        // Divide work evenly among threads
        const chunk_size = input.len / self.thread_count;

        // Thread context

        var contexts = try self.allocator.alloc(ThreadContext, self.thread_count);
        defer self.allocator.free(contexts);

        const threads = try self.allocator.alloc(std.Thread, self.thread_count);
        defer self.allocator.free(threads);

        var temp_buffers = try self.allocator.alloc([]u8, self.thread_count);
        defer {
            for (temp_buffers) |buf| {
                if (buf.len > 0) self.allocator.free(buf);
            }
            self.allocator.free(temp_buffers);
        }

        // Initialize contexts and buffers
        var offset: usize = 0;
        for (0..self.thread_count) |i| {
            const start = offset;
            const end = if (i == self.thread_count - 1) input.len else start + chunk_size;

            temp_buffers[i] = try self.allocator.alloc(u8, end - start);

            contexts[i] = .{
                .input = input[start..end],
                .output = temp_buffers[i],
                .result = 0,
                .err = null,
            };

            offset = end;
        }

        // Start threads
        for (threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, threadWorker, .{&contexts[i]});
        }

        // Wait for completion
        for (threads) |thread| {
            thread.join();
        }

        // Check for errors
        for (contexts) |ctx| {
            if (ctx.err) |err| return err;
        }

        // Merge results
        var total: usize = 0;
        for (contexts) |ctx| {
            if (total + ctx.result > output.len) {
                return error.OutputBufferTooSmall;
            }
            @memcpy(output[total .. total + ctx.result], ctx.output[0..ctx.result]);
            total += ctx.result;
        }

        return total;
    }

    const ThreadContext = struct {
        input: []const u8,
        output: []u8,
        result: usize,
        err: ?anyerror,
    };

    fn threadWorker(ctx: *ThreadContext) void {
        ctx.result = minifyChunk(ctx.input, ctx.output) catch |err| {
            ctx.err = err;
            return;
        };
    }

    fn minifyChunk(input: []const u8, output: []u8) !usize {
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;

        while (i < input.len) {
            const c = input[i];

            if (in_string) {
                output[out_pos] = c;
                out_pos += 1;

                if (c == '\\' and !escaped) {
                    escaped = true;
                } else if (c == '"' and !escaped) {
                    in_string = false;
                    escaped = false;
                } else {
                    escaped = false;
                }
            } else {
                if (c == '"') {
                    output[out_pos] = c;
                    out_pos += 1;
                    in_string = true;
                } else if (!isWhitespace(c)) {
                    output[out_pos] = c;
                    out_pos += 1;
                }
            }

            i += 1;
        }

        return out_pos;
    }

    inline fn isWhitespace(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\nTesting Simple Parallel Implementation\n", .{});
    try stdout.print("=====================================\n\n", .{});

    // Test input
    const test_input =
        \\{
        \\  "name": "test",
        \\  "value": 123,
        \\  "array": [1, 2, 3],
        \\  "nested": {
        \\    "key": "value"
        \\  }
        \\}
    ;

    const output = try allocator.alloc(u8, test_input.len);
    defer allocator.free(output);

    // Test with 1 thread
    var single_thread = try TurboMinifierParallelSimple.init(allocator, .{ .thread_count = 1 });
    defer single_thread.deinit();

    const single_len = try single_thread.minify(test_input, output);
    try stdout.print("Single thread result: {s}\n", .{output[0..single_len]});

    // Test with multiple threads
    var multi_thread = try TurboMinifierParallelSimple.init(allocator, .{ .thread_count = 4 });
    defer multi_thread.deinit();

    const multi_len = try multi_thread.minify(test_input, output);
    try stdout.print("Multi thread result:  {s}\n", .{output[0..multi_len]});

    // Test larger input
    const large_size = 10 * 1024 * 1024;
    const large_input = try generateTestJson(allocator, large_size);
    defer allocator.free(large_input);

    const large_output = try allocator.alloc(u8, large_input.len);
    defer allocator.free(large_output);

    try stdout.print("\nTesting {d} MB file...\n", .{large_size / 1024 / 1024});

    const start = std.time.milliTimestamp();
    const result_len = try multi_thread.minify(large_input, large_output);
    const end = std.time.milliTimestamp();

    try stdout.print("Processed in {d} ms\n", .{end - start});
    try stdout.print("Output size: {d} bytes\n", .{result_len});
    try stdout.print("Reduction: {d:.1}%\n", .{(1.0 - @as(f64, @floatFromInt(result_len)) / @as(f64, @floatFromInt(large_input.len))) * 100.0});
}

fn generateTestJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("{\n");

    var key_counter: usize = 0;
    while (buffer.items.len < target_size - 100) {
        if (key_counter > 0) {
            try buffer.appendSlice(",\n");
        }

        const pattern = key_counter % 3;
        switch (pattern) {
            0 => try buffer.writer().print("  \"key_{d}\"  :  \"value with    spaces\"", .{key_counter}),
            1 => try buffer.writer().print("  \"data_{d}\" : {{ \"num\" : {d} }}", .{ key_counter, key_counter * 42 }),
            2 => try buffer.writer().print("  \"arr_{d}\" : [  1,   2,    3  ]", .{key_counter}),
            else => unreachable,
        }

        key_counter += 1;
    }

    try buffer.appendSlice("\n}");
    return buffer.toOwnedSlice();
}
