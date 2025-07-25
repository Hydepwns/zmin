const std = @import("std");
const testing = std.testing;
const config = @import("src").parallel.config;

test "config validation - valid config" {
    const valid_config = config.Config{
        .thread_count = 4,
        .chunk_size = 1024,
    };

    try valid_config.validate();
}

test "config validation - invalid chunk size" {
    const invalid_config = config.Config{
        .thread_count = 4,
        .chunk_size = 0,
    };

    try testing.expectError(error.InvalidChunkSize, invalid_config.validate());
}

test "config optimal thread count - zero threads" {
    const config_options = config.Config{
        .thread_count = 0,
        .chunk_size = 1024,
    };

    const optimal_count = config_options.getOptimalThreadCount();
    try testing.expect(optimal_count >= 1);
}

test "config optimal thread count - high thread count" {
    const config_options = config.Config{
        .thread_count = 1000,
        .chunk_size = 1024,
    };

    const optimal_count = config_options.getOptimalThreadCount();
    const max_threads = std.Thread.getCpuCount() catch 4;
    try testing.expect(optimal_count <= max_threads);
}

test "work item creation" {
    const chunk = "{\"test\":\"value\"}";
    const work_item = config.WorkItem.init(chunk, 42, true);

    try testing.expectEqualStrings(chunk, work_item.chunk);
    try testing.expectEqual(@as(usize, 42), work_item.chunk_id);
    try testing.expect(work_item.is_final);
}

test "chunk result creation and cleanup" {
    const output = "minified";
    const output_copy = try testing.allocator.alloc(u8, output.len);
    @memcpy(output_copy, output);

    const result = config.ChunkResult.init(123, output_copy);

    try testing.expectEqual(@as(usize, 123), result.chunk_id);
    try testing.expectEqualStrings(output, result.output);

    // Test deinit (should not crash)
    var result_copy = result;
    result_copy.deinit(testing.allocator);
}

test "performance stats initialization" {
    const stats = config.PerformanceStats.init();

    try testing.expectEqual(@as(f64, 0.0), stats.throughput_mbps);
    try testing.expectEqual(@as(f64, 0.0), stats.thread_utilization);
    try testing.expectEqual(@as(usize, 0), stats.memory_usage);
    try testing.expectEqual(@as(u64, 0), stats.bytes_processed);
    try testing.expectEqual(@as(u64, 0), stats.processing_time_ms);
}
