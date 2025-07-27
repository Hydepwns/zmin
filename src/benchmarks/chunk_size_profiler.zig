// Comprehensive chunk size profiler for parallel JSON minification
const std = @import("std");
const TurboMinifierParallelSimple = @import("../modes/turbo_minifier_parallel_simple.zig").TurboMinifierParallelSimple;

pub const ChunkSizeProfiler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ChunkSizeProfiler {
        return ChunkSizeProfiler{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ChunkSizeProfiler) void {
        _ = self;
    }

    // Profile different chunk sizes across various file sizes and thread counts
    pub fn profileChunkSizes(self: *ChunkSizeProfiler) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\n📊 Chunk Size Profiler\n", .{});
        try stdout.print("======================\n\n", .{});

        // Test parameters
        const file_sizes = [_]struct { size: usize, name: []const u8 }{
            .{ .size = 1024 * 1024, .name = "1 MB" },
            .{ .size = 10 * 1024 * 1024, .name = "10 MB" },
            .{ .size = 50 * 1024 * 1024, .name = "50 MB" },
            .{ .size = 100 * 1024 * 1024, .name = "100 MB" },
        };

        const thread_counts = [_]usize{ 2, 4, 8, 16 };

        // Chunk sizes to test (in KB)
        const chunk_sizes_kb = [_]usize{
            16, // 16KB - Very small chunks
            64, // 64KB - Small chunks
            256, // 256KB - Medium chunks
            1024, // 1MB - Large chunks
            4096, // 4MB - Very large chunks
            16384, // 16MB - Huge chunks
        };

        // Test each combination
        for (file_sizes) |file_case| {
            try stdout.print("🔍 Testing {s} file:\n", .{file_case.name});

            const input = try self.generateTestJson(file_case.size);
            defer self.allocator.free(input);

            for (thread_counts) |thread_count| {
                const cpu_count = try std.Thread.getCpuCount();
                if (thread_count > cpu_count) continue;

                try stdout.print("\n  📈 {d} threads:\n", .{thread_count});
                try stdout.print("    Chunk Size | Throughput |  Time  | Efficiency\n", .{});
                try stdout.print("    -----------|------------|--------|------------\n", .{});

                var best_throughput: f64 = 0;
                var best_chunk_size: usize = 0;

                for (chunk_sizes_kb) |chunk_kb| {
                    const chunk_size = chunk_kb * 1024;

                    // Skip if chunk size is larger than file
                    if (chunk_size > file_case.size) continue;

                    const result = try self.benchmarkChunkSize(input, thread_count, chunk_size);

                    if (result.throughput > best_throughput) {
                        best_throughput = result.throughput;
                        best_chunk_size = chunk_kb;
                    }

                    try stdout.print("    {d:>7} KB | {d:>8.1} MB/s | {d:>4} ms | {d:>6.1}%\n", .{
                        chunk_kb,
                        result.throughput,
                        result.time_ms,
                        result.efficiency,
                    });
                }

                try stdout.print("    → Best: {d} KB ({d:.1} MB/s)\n", .{ best_chunk_size, best_throughput });
            }

            try stdout.print("\n", .{});
        }

        // Test adaptive chunk sizing
        try self.testAdaptiveChunking();
    }

    // Benchmark a specific chunk size configuration
    fn benchmarkChunkSize(self: *ChunkSizeProfiler, input: []const u8, thread_count: usize, chunk_size: usize) !BenchmarkResult {
        const output = try self.allocator.alloc(u8, input.len);
        defer self.allocator.free(output);

        // Create modified minifier with custom chunk size
        var minifier = CustomChunkMinifier{
            .allocator = self.allocator,
            .thread_count = thread_count,
            .chunk_size = chunk_size,
        };

        // Warm up
        _ = try minifier.minify(input[0..@min(chunk_size, input.len)], output);

        // Benchmark multiple runs for accuracy
        const runs = 3;
        var total_time: u64 = 0;

        for (0..runs) |_| {
            const start = std.time.nanoTimestamp();
            _ = try minifier.minify(input, output);
            const end = std.time.nanoTimestamp();
            total_time += @intCast(end - start);
        }

        const avg_time_ns = total_time / runs;
        const time_ms = avg_time_ns / 1_000_000;
        const throughput = if (time_ms > 0)
            (@as(f64, @floatFromInt(input.len)) / @as(f64, @floatFromInt(time_ms)) * 1000.0 / (1024.0 * 1024.0))
        else
            0.0;

        // Calculate efficiency as percentage of ideal linear speedup
        const single_thread_estimate = throughput / @as(f64, @floatFromInt(thread_count));
        const ideal_throughput = single_thread_estimate * @as(f64, @floatFromInt(thread_count));
        const efficiency = if (ideal_throughput > 0)
            (throughput / ideal_throughput * 100.0)
        else
            0.0;

        return BenchmarkResult{
            .throughput = throughput,
            .time_ms = time_ms,
            .efficiency = efficiency,
        };
    }

    // Test adaptive chunk sizing based on file size and thread count
    fn testAdaptiveChunking(self: *ChunkSizeProfiler) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("🧠 Adaptive Chunk Sizing Analysis\n", .{});
        try stdout.print("==================================\n\n", .{});

        const test_cases = [_]struct { file_size: usize, threads: usize, name: []const u8 }{
            .{ .file_size = 1024 * 1024, .threads = 4, .name = "1MB / 4 threads" },
            .{ .file_size = 10 * 1024 * 1024, .threads = 8, .name = "10MB / 8 threads" },
            .{ .file_size = 100 * 1024 * 1024, .threads = 16, .name = "100MB / 16 threads" },
        };

        for (test_cases) |case| {
            try stdout.print("📋 {s}:\n", .{case.name});

            const input = try self.generateTestJson(case.file_size);
            defer self.allocator.free(input);

            // Test different chunk sizing strategies
            const strategies = [_]struct { chunk_size: usize, name: []const u8 }{
                .{ .chunk_size = case.file_size / case.threads, .name = "Equal division" },
                .{ .chunk_size = case.file_size / (case.threads * 2), .name = "2x threads" },
                .{ .chunk_size = case.file_size / (case.threads * 4), .name = "4x threads" },
                .{ .chunk_size = 256 * 1024, .name = "Fixed 256KB" },
                .{ .chunk_size = 1024 * 1024, .name = "Fixed 1MB" },
            };

            for (strategies) |strategy| {
                if (strategy.chunk_size == 0) continue;

                const result = try self.benchmarkChunkSize(input, case.threads, strategy.chunk_size);
                try stdout.print("  {s:<15}: {d:>7.1} MB/s ({d:>5.1}% eff)\n", .{
                    strategy.name,
                    result.throughput,
                    result.efficiency,
                });
            }

            try stdout.print("\n", .{});
        }
    }

    fn generateTestJson(self: *ChunkSizeProfiler, target_size: usize) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try buffer.appendSlice("{\n");

        var key_counter: usize = 0;
        while (buffer.items.len < target_size - 100) {
            if (key_counter > 0) {
                try buffer.appendSlice(",\n");
            }

            const pattern = key_counter % 5;
            switch (pattern) {
                0 => try buffer.writer().print("  \"key_{d}\"  :  \"value with    spaces    and more\"", .{key_counter}),
                1 => try buffer.writer().print("  \"data_{d}\" : {{   \"num\" :   {d},   \"str\" : \"test\"   }}", .{ key_counter, key_counter * 42 }),
                2 => try buffer.writer().print("  \"array_{d}\" : [  1,   2,    3,     4,      5  ]", .{key_counter}),
                3 => try buffer.writer().print("  \"nested_{d}\" : {{  \"a\" : {{  \"b\" :  \"c\"  }}  }}", .{key_counter}),
                4 => try buffer.writer().print("  \"long_string_{d}\" : \"This is a longer string value that contains more content to increase the size and test different patterns\"", .{key_counter}),
                else => unreachable,
            }

            key_counter += 1;
        }

        try buffer.appendSlice("\n}");
        return buffer.toOwnedSlice();
    }

    const BenchmarkResult = struct {
        throughput: f64,
        time_ms: u64,
        efficiency: f64,
    };

    // Custom minifier with configurable chunk size
    const CustomChunkMinifier = struct {
        allocator: std.mem.Allocator,
        thread_count: usize,
        chunk_size: usize,

        fn minify(self: *CustomChunkMinifier, input: []const u8, output: []u8) !usize {
            if (input.len < self.chunk_size or self.thread_count == 1) {
                return minifyChunk(input, output);
            }

            const num_chunks = (input.len + self.chunk_size - 1) / self.chunk_size;
            const actual_threads = @min(self.thread_count, num_chunks);

            var contexts = try self.allocator.alloc(ThreadContext, actual_threads);
            defer self.allocator.free(contexts);

            const threads = try self.allocator.alloc(std.Thread, actual_threads);
            defer self.allocator.free(threads);

            var temp_buffers = try self.allocator.alloc([]u8, actual_threads);
            defer {
                for (temp_buffers) |buf| {
                    if (buf.len > 0) self.allocator.free(buf);
                }
                self.allocator.free(temp_buffers);
            }

            // Distribute chunks among threads
            var offset: usize = 0;
            for (0..actual_threads) |i| {
                const start = offset;
                const chunks_per_thread = num_chunks / actual_threads +
                    (if (i < num_chunks % actual_threads) @as(usize, 1) else 0);
                const end = @min(start + chunks_per_thread * self.chunk_size, input.len);

                temp_buffers[i] = try self.allocator.alloc(u8, end - start);

                contexts[i] = ThreadContext{
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

        fn threadWorker(ctx: *ThreadContext) void {
            const context = ctx;
            context.result = minifyChunk(context.input, context.output) catch |err| {
                context.err = err;
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

        const ThreadContext = struct {
            input: []const u8,
            output: []u8,
            result: usize,
            err: ?anyerror,
        };
    };
};
