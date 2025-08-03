//! Example: Migrating to Common Modules
//!
//! This example demonstrates how to update existing code to use the new
//! common modules for improved code reuse and consistency.

const std = @import("std");

// Import new common modules
const constants = @import("common/constants.zig");
const benchmark_utils = @import("common/benchmark_utils.zig");
const chunk_utils = @import("common/chunk_utils.zig");
const json_utils = @import("common/json_utils.zig");
const buffer_utils = @import("common/buffer_utils.zig");
const work_queue = @import("common/work_queue.zig");

// Before: Hardcoded constants scattered throughout
const OLD_CHUNK_SIZE = 64 * 1024;
const OLD_BUFFER_SIZE = 256 * 1024;
const OLD_CACHE_LINE = 64;

// After: Use centralized constants
const CHUNK_SIZE = constants.Chunk.MEDIUM;
const BUFFER_SIZE = constants.Buffer.LARGE;
const CACHE_LINE = constants.System.CACHE_LINE_SIZE;

// Before: Manual timing code
fn oldBenchmark(data: []const u8) !void {
    const start = std.time.nanoTimestamp();
    
    // Process data...
    processData(data);
    
    const end = std.time.nanoTimestamp();
    const elapsed_ns = end - start;
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
    const throughput = @as(f64, @floatFromInt(data.len)) / (1024.0 * 1024.0) / elapsed_s;
    
    std.debug.print("Throughput: {d:.2} MB/s\n", .{throughput});
}

// After: Use benchmark utilities
fn newBenchmark(data: []const u8) !void {
    const result = try benchmark_utils.measurePerformance(processData, .{data}, data.len);
    std.debug.print("Result: {}\n", .{result});
}

// Before: Manual chunk size calculation
fn oldCalculateChunkSize(file_size: usize, thread_count: usize) usize {
    var chunk_size: usize = 64 * 1024;
    
    if (file_size < 1024) {
        chunk_size = 1024;
    } else if (file_size < 64 * 1024) {
        chunk_size = 16 * 1024;
    } else if (file_size < 1024 * 1024) {
        chunk_size = 64 * 1024;
    } else {
        chunk_size = 256 * 1024;
    }
    
    // Ensure enough chunks for threads
    const min_chunks = thread_count * 4;
    const max_chunk_size = file_size / min_chunks;
    chunk_size = @min(chunk_size, max_chunk_size);
    
    return chunk_size;
}

// After: Use chunk utilities
fn newCalculateChunkSize(file_size: usize, thread_count: usize) usize {
    const params = chunk_utils.ChunkParams{
        .data_size = file_size,
        .thread_count = thread_count,
    };
    
    const recommendation = chunk_utils.calculateOptimalChunkSize(params);
    return recommendation.size;
}

// Before: Manual JSON validation
fn oldValidateJson(input: []const u8) !void {
    var depth: u32 = 0;
    var in_string = false;
    var escape = false;
    
    for (input, 0..) |c, i| {
        if (in_string) {
            if (escape) {
                escape = false;
            } else if (c == '\\') {
                escape = true;
            } else if (c == '"') {
                in_string = false;
            }
        } else {
            switch (c) {
                '{', '[' => {
                    depth += 1;
                    if (depth > 1000) return error.DepthLimit;
                },
                '}', ']' => {
                    if (depth == 0) return error.UnbalancedBrackets;
                    depth -= 1;
                },
                '"' => in_string = true,
                else => {},
            }
        }
    }
    
    if (depth != 0) return error.UnbalancedBrackets;
}

// After: Use JSON utilities
fn newValidateJson(input: []const u8) !void {
    try json_utils.validateJson(input);
}

// Before: Manual buffer management
const OldBuffer = struct {
    data: []u8,
    len: usize,
    capacity: usize,
    allocator: std.mem.Allocator,
    
    fn init(allocator: std.mem.Allocator, capacity: usize) !OldBuffer {
        return OldBuffer{
            .data = try allocator.alloc(u8, capacity),
            .len = 0,
            .capacity = capacity,
            .allocator = allocator,
        };
    }
    
    fn deinit(self: *OldBuffer) void {
        self.allocator.free(self.data);
    }
    
    fn append(self: *OldBuffer, bytes: []const u8) !void {
        if (self.len + bytes.len > self.capacity) {
            // Manual reallocation
            const new_capacity = self.capacity * 2;
            const new_data = try self.allocator.realloc(self.data, new_capacity);
            self.data = new_data;
            self.capacity = new_capacity;
        }
        @memcpy(self.data[self.len..self.len + bytes.len], bytes);
        self.len += bytes.len;
    }
};

// After: Use buffer utilities
fn useNewBuffer(allocator: std.mem.Allocator) !void {
    var buffer = try buffer_utils.DynamicBuffer.init(allocator, constants.Buffer.MEDIUM);
    defer buffer.deinit();
    
    try buffer.append("Hello, ");
    try buffer.append("World!");
    
    std.debug.print("Buffer: {s}\n", .{buffer.slice()});
}

// Before: Manual work queue implementation
const OldWorkQueue = struct {
    items: []WorkItem,
    head: usize,
    tail: usize,
    mutex: std.Thread.Mutex,
    
    const WorkItem = struct {
        id: u32,
        data: []const u8,
    };
    
    // ... lots of manual implementation
};

// After: Use work queue utilities
fn useNewWorkQueue(allocator: std.mem.Allocator) !void {
    var scheduler = try work_queue.WorkStealingScheduler.init(allocator, .{
        .thread_count = 4,
        .queue_capacity = 1024,
        .steal_strategy = .work_guided,
    });
    defer scheduler.deinit();
    
    // Submit work items
    const item = work_queue.WorkItem{
        .id = 1,
        .data = undefined,
        .execute_fn = processWorkItem,
    };
    
    _ = scheduler.submit(item);
    
    // Start processing
    try scheduler.start();
    defer scheduler.stop();
}

// Example: Complete migration of a benchmark
pub fn migratedBenchmarkExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Setup benchmark suite
    var suite = benchmark_utils.BenchmarkSuite.init(allocator, "JSON Processing");
    defer suite.deinit();
    
    // Generate test data using fixtures
    const test_data = try buffer_utils.JsonBuilder.init(allocator);
    defer test_data.deinit();
    
    // Build test JSON
    var builder = try buffer_utils.JsonBuilder.init(allocator);
    defer builder.deinit();
    
    try builder.startObject();
    for (0..1000) |i| {
        var key_buf: [32]u8 = undefined;
        const key = try std.fmt.bufPrint(&key_buf, "field_{}", .{i});
        try builder.addKey(key);
        try builder.addNumber(i);
    }
    try builder.endObject();
    
    const json_data = builder.slice();
    
    // Validate JSON
    try json_utils.validateJson(json_data);
    
    // Calculate optimal chunk size
    const chunk_size = chunk_utils.calculateOptimalChunkSize(.{
        .data_size = json_data.len,
        .thread_count = try std.Thread.getCpuCount(),
    }).size;
    
    std.debug.print("Using chunk size: {}\n", .{std.fmt.fmtIntSizeDec(chunk_size)});
    
    // Run benchmarks
    try suite.addBenchmark("Single-threaded", processSingleThreaded, .{json_data}, json_data.len);
    try suite.addBenchmark("Multi-threaded", processMultiThreaded, .{json_data}, json_data.len);
    
    // Print results
    suite.printResults();
}

// Helper functions
fn processData(data: []const u8) void {
    _ = data;
    // Simulate processing
    std.time.sleep(1000);
}

fn processWorkItem(data: *anyopaque) !void {
    _ = data;
    // Process work item
}

fn processSingleThreaded(data: []const u8) !void {
    _ = data;
    // Single-threaded processing
}

fn processMultiThreaded(data: []const u8) !void {
    _ = data;
    // Multi-threaded processing
}

pub fn main() !void {
    std.debug.print("=== Migration Example ===\n\n", .{});
    
    // Show constant usage
    std.debug.print("Constants:\n", .{});
    std.debug.print("  Cache line size: {}\n", .{constants.System.CACHE_LINE_SIZE});
    std.debug.print("  Default chunk: {}\n", .{constants.Format.bytes(constants.Chunk.DEFAULT)});
    std.debug.print("  L2 cache: {}\n", .{constants.Format.bytes(constants.Cache.L2_SIZE)});
    std.debug.print("\n", .{});
    
    // Run migrated benchmark
    try migratedBenchmarkExample();
}