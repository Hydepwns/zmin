//! Parallel batch processing example for zmin
//!
//! This example demonstrates how to efficiently process multiple JSON files
//! in parallel using work-stealing and thread pools.

const std = @import("std");
const zmin = @import("zmin_lib");

const WorkItem = struct {
    input_path: []const u8,
    output_path: []const u8,
    status: enum { pending, processing, completed, failed } = .pending,
    error_msg: ?[]const u8 = null,
    stats: ?Stats = null,
};

const Stats = struct {
    input_size: usize,
    output_size: usize,
    duration_us: u64,
};

const BatchProcessor = struct {
    allocator: std.mem.Allocator,
    work_queue: std.ArrayList(WorkItem),
    work_queue_mutex: std.Thread.Mutex,
    work_index: std.atomic.Value(usize),
    results: std.ArrayList(WorkItem),
    results_mutex: std.Thread.Mutex,
    thread_count: u32,
    mode: zmin.ProcessingMode,

    pub fn init(
        allocator: std.mem.Allocator,
        thread_count: u32,
        mode: zmin.ProcessingMode,
    ) BatchProcessor {
        return .{
            .allocator = allocator,
            .work_queue = std.ArrayList(WorkItem).init(allocator),
            .work_queue_mutex = std.Thread.Mutex{},
            .work_index = std.atomic.Value(usize).init(0),
            .results = std.ArrayList(WorkItem).init(allocator),
            .results_mutex = std.Thread.Mutex{},
            .thread_count = thread_count,
            .mode = mode,
        };
    }

    pub fn deinit(self: *BatchProcessor) void {
        self.work_queue.deinit();
        self.results.deinit();
    }

    pub fn addWork(self: *BatchProcessor, input: []const u8, output: []const u8) !void {
        const work = WorkItem{
            .input_path = try self.allocator.dupe(u8, input),
            .output_path = try self.allocator.dupe(u8, output),
        };

        self.work_queue_mutex.lock();
        defer self.work_queue_mutex.unlock();
        try self.work_queue.append(work);
    }

    pub fn process(self: *BatchProcessor) !void {
        const stdout = std.io.getStdOut().writer();

        // Start worker threads
        const threads = try self.allocator.alloc(std.Thread, self.thread_count);
        defer self.allocator.free(threads);

        try stdout.print("Starting {d} worker threads...\n", .{self.thread_count});

        for (threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, worker, .{ self, i });
        }

        // Wait for all threads to complete
        for (threads) |thread| {
            thread.join();
        }
    }

    fn worker(self: *BatchProcessor, thread_id: usize) !void {
        const thread_allocator = std.heap.page_allocator; // Each thread gets its own allocator

        while (true) {
            // Get next work item
            const idx = self.work_index.fetchAdd(1, .monotonic);
            
            self.work_queue_mutex.lock();
            const queue_len = self.work_queue.items.len;
            self.work_queue_mutex.unlock();
            
            if (idx >= queue_len) break;
            
            self.work_queue_mutex.lock();
            var work = self.work_queue.items[idx];
            self.work_queue_mutex.unlock();

            work.status = .processing;

            // Process the file
            const result = self.processFile(thread_allocator, &work);

            // Store result
            self.results_mutex.lock();
            defer self.results_mutex.unlock();

            if (result) |_| {
                work.status = .completed;
            } else |err| {
                work.status = .failed;
                work.error_msg = @errorName(err);
            }

            try self.results.append(work);

            // Progress update
            const stdout = std.io.getStdOut().writer();
            stdout.print("[Thread {d}] Processed: {s}\n", .{ thread_id, work.input_path }) catch {};
        }
    }

    fn processFile(self: *BatchProcessor, allocator: std.mem.Allocator, work: *WorkItem) !void {
        // Read input
        const input = try std.fs.cwd().readFileAlloc(allocator, work.input_path, 100 * 1024 * 1024);
        defer allocator.free(input);

        const start = std.time.microTimestamp();

        // Minify
        const output = try zmin.minifyWithMode(allocator, input, self.mode);
        defer allocator.free(output);

        const duration = @as(u64, @intCast(std.time.microTimestamp() - start));

        // Write output
        try std.fs.cwd().writeFile(.{ .sub_path = work.output_path, .data = output });

        // Record stats
        work.stats = Stats{
            .input_size = input.len,
            .output_size = output.len,
            .duration_us = duration,
        };
    }

    pub fn printReport(self: *BatchProcessor) !void {
        const stdout = std.io.getStdOut().writer();

        try stdout.print("\n=== Batch Processing Report ===\n", .{});

        var total_input: usize = 0;
        var total_output: usize = 0;
        var total_time: u64 = 0;
        var success_count: u32 = 0;
        var fail_count: u32 = 0;

        for (self.results.items) |work| {
            if (work.status == .completed) {
                success_count += 1;
                if (work.stats) |stats| {
                    total_input += stats.input_size;
                    total_output += stats.output_size;
                    total_time += stats.duration_us;
                }
            } else {
                fail_count += 1;
                try stdout.print("  ❌ Failed: {s}", .{work.input_path});
                if (work.error_msg) |msg| {
                    try stdout.print(" - {s}", .{msg});
                }
                try stdout.print("\n", .{});
            }
        }

        try stdout.print("\nSummary:\n", .{});
        try stdout.print("  Files processed: {d}\n", .{success_count});
        try stdout.print("  Files failed: {d}\n", .{fail_count});

        if (success_count > 0) {
            const avg_time = total_time / success_count;
            const compression = @as(f32, @floatFromInt(total_input - total_output)) /
                @as(f32, @floatFromInt(total_input)) * 100;
            const throughput = @as(f32, @floatFromInt(total_input)) /
                @as(f32, @floatFromInt(total_time));

            try stdout.print("  Total input: {d} bytes\n", .{total_input});
            try stdout.print("  Total output: {d} bytes\n", .{total_output});
            try stdout.print("  Compression: {d:.1}%\n", .{compression});
            try stdout.print("  Average time: {d} µs/file\n", .{avg_time});
            try stdout.print("  Throughput: {d:.0} MB/s\n", .{throughput});
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    try stdout.print("=== Parallel Batch Processing Example ===\n\n", .{});

    // Example 1: Process directory
    try example1_process_directory(allocator);

    // Example 2: Work stealing demonstration
    try example2_work_stealing(allocator);

    // Example 3: Dynamic load balancing
    try example3_load_balancing(allocator);
}

fn example1_process_directory(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Example 1: Process all JSON files in directory\n", .{});

    // Create test files
    try createTestFiles(allocator, "test_batch", 10);
    defer cleanupTestFiles("test_batch", 10) catch {};

    // Setup batch processor
    const cpu_count = try std.Thread.getCpuCount();
    var processor = BatchProcessor.init(allocator, @intCast(cpu_count), .turbo);
    defer processor.deinit();

    // Add all JSON files to work queue
    var count: u32 = 0;
    for (0..10) |i| {
        const input = try std.fmt.allocPrint(allocator, "test_batch/file_{d}.json", .{i});
        defer allocator.free(input);
        const output = try std.fmt.allocPrint(allocator, "test_batch/file_{d}.min.json", .{i});
        defer allocator.free(output);

        try processor.addWork(input, output);
        count += 1;
    }

    try stdout.print("Added {d} files to work queue\n", .{count});

    // Process in parallel
    const start = std.time.milliTimestamp();
    try processor.process();
    const duration = std.time.milliTimestamp() - start;

    try stdout.print("Total processing time: {d} ms\n", .{duration});

    // Print report
    try processor.printReport();
}

fn example2_work_stealing(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n\nExample 2: Work Stealing Demonstration\n", .{});
    try stdout.print("Creating files with varying sizes to show work stealing...\n", .{});

    // Create files with different sizes
    const sizes = [_]u32{ 10, 100, 50, 200, 30, 150, 80, 120, 40, 180 };

    for (sizes, 0..) |size, i| {
        const filename = try std.fmt.allocPrint(allocator, "test_batch/varied_{d}.json", .{i});
        defer allocator.free(filename);

        const content = try generateJsonWithSize(allocator, size);
        defer allocator.free(content);

        try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
    }
    defer {
        for (0..sizes.len) |i| {
            const filename = std.fmt.allocPrintZ(allocator, "test_batch/varied_{d}.json", .{i}) catch continue;
            defer allocator.free(filename);
            std.fs.cwd().deleteFile(filename) catch {};

            const minified = std.fmt.allocPrintZ(allocator, "test_batch/varied_{d}.min.json", .{i}) catch continue;
            defer allocator.free(minified);
            std.fs.cwd().deleteFile(minified) catch {};
        }
    }

    // Process with multiple threads
    var processor = BatchProcessor.init(allocator, 4, .sport);
    defer processor.deinit();

    for (sizes, 0..) |_, i| {
        const input = try std.fmt.allocPrint(allocator, "test_batch/varied_{d}.json", .{i});
        defer allocator.free(input);
        const output = try std.fmt.allocPrint(allocator, "test_batch/varied_{d}.min.json", .{i});
        defer allocator.free(output);

        try processor.addWork(input, output);
    }

    try processor.process();
    try processor.printReport();
}

fn example3_load_balancing(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("\n\nExample 3: Dynamic Load Balancing\n", .{});
    try stdout.print("Comparing different thread counts...\n\n", .{});

    // Create consistent test set
    try createTestFiles(allocator, "test_batch", 20);
    defer cleanupTestFiles("test_batch", 20) catch {};

    const thread_counts = [_]u32{ 1, 2, 4, 8 };

    for (thread_counts) |thread_count| {
        var processor = BatchProcessor.init(allocator, thread_count, .turbo);
        defer processor.deinit();

        // Add work
        for (0..20) |i| {
            const input = try std.fmt.allocPrint(allocator, "test_batch/file_{d}.json", .{i});
            defer allocator.free(input);
            const output = try std.fmt.allocPrint(allocator, "test_batch/file_{d}.min.json", .{i});
            defer allocator.free(output);

            try processor.addWork(input, output);
        }

        const start = std.time.milliTimestamp();
        try processor.process();
        const duration = std.time.milliTimestamp() - start;

        try stdout.print("Threads: {d: >2} - Time: {d: >4} ms\n", .{ thread_count, duration });
    }
}

fn createTestFiles(allocator: std.mem.Allocator, dir: []const u8, count: u32) !void {
    // Create directory
    std.fs.cwd().makeDir(dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Create test JSON files
    for (0..count) |i| {
        const filename = try std.fmt.allocPrint(allocator, "{s}/file_{d}.json", .{ dir, i });
        defer allocator.free(filename);

        const content = try generateJsonWithSize(allocator, 100);
        defer allocator.free(content);

        try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
    }
}

fn cleanupTestFiles(dir: []const u8, count: u32) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Delete files
    for (0..count) |i| {
        const json_file = try std.fmt.allocPrint(allocator, "{s}/file_{d}.json", .{ dir, i });
        std.fs.cwd().deleteFile(json_file) catch {};

        const min_file = try std.fmt.allocPrint(allocator, "{s}/file_{d}.min.json", .{ dir, i });
        std.fs.cwd().deleteFile(min_file) catch {};
    }

    // Try to remove directory
    std.fs.cwd().deleteDir(dir) catch {};
}

fn generateJsonWithSize(allocator: std.mem.Allocator, items: u32) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);
    var writer = json.writer();

    try writer.writeAll("{\n  \"data\": [\n");

    for (0..items) |i| {
        if (i > 0) try writer.writeAll(",\n");
        try writer.print("    {{ \"id\": {d}, \"value\": \"Item {d}\" }}", .{ i, i });
    }

    try writer.writeAll("\n  ]\n}");

    return json.toOwnedSlice();
}
