const std = @import("std");
const testing = std.testing;
const chunk_processor = @import("src").parallel.chunk_processor;
const config = @import("src").parallel.config;

test "chunk processor initialization" {
    _ = chunk_processor.ChunkProcessor.init(testing.allocator);
    try testing.expect(true); // Should not crash
}

test "chunk processor basic processing" {
    var processor = chunk_processor.ChunkProcessor.init(testing.allocator);
    const work_item = config.WorkItem.init("{\"key\":\"value\"}", 1, false);

    var result = try processor.processChunk(work_item);
    defer result.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), result.chunk_id);
    try testing.expectEqualStrings("{\"key\":\"value\"}", result.output);
}

test "chunk processor with writer" {
    var processor = chunk_processor.ChunkProcessor.init(testing.allocator);
    const work_item = config.WorkItem.init("{\"test\":123}", 1, false);

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    try processor.processChunkWithWriter(work_item, output.writer().any());
    try testing.expectEqualStrings("{\"test\":123}", output.items);
}

test "chunk processor pretty printing" {
    var processor = chunk_processor.ChunkProcessor.init(testing.allocator);
    const work_item = config.WorkItem.init("{\"key\":\"value\"}", 1, false);

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    try processor.processChunkPretty(work_item, output.writer().any(), 2);

    // Should be pretty printed with indentation
    try testing.expect(output.items.len > work_item.chunk.len);
    try testing.expect(std.mem.indexOf(u8, output.items, "\n") != null);
}

test "chunk processor chunk size estimation" {
    var processor = chunk_processor.ChunkProcessor.init(testing.allocator);

    const input = "{\"key1\":\"value1\",\"key2\":\"value2\",\"key3\":\"value3\"}";
    const target_size = 10;

    const estimated_size = try processor.estimateChunkSize(input, target_size);
    try testing.expect(estimated_size <= input.len);
    try testing.expect(estimated_size > 0);
}

test "chunk processor split into chunks" {
    var processor = chunk_processor.ChunkProcessor.init(testing.allocator);

    const input = "{\"key1\":\"value1\",\"key2\":\"value2\",\"key3\":\"value3\"}";
    const chunk_size = 15;

    const chunks = try processor.splitIntoChunks(input, chunk_size);
    defer testing.allocator.free(chunks);

    try testing.expect(chunks.len > 0);

    // Verify all chunks together contain the original input
    var reconstructed = std.ArrayList(u8).init(testing.allocator);
    defer reconstructed.deinit();

    for (chunks) |chunk| {
        try reconstructed.appendSlice(chunk.chunk);
    }

    try testing.expectEqualStrings(input, reconstructed.items);
}

test "chunk processor validation" {
    var processor = chunk_processor.ChunkProcessor.init(testing.allocator);

    // Valid JSON should not error
    try processor.validateChunk("{\"valid\":\"json\"}");

    // Invalid JSON should error
    try testing.expectError(error.InvalidValue, processor.validateChunk("{\"invalid\":json}"));
}
