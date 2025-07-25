const std = @import("std");
const testing = std.testing;
const work_queue = @import("src").parallel.work_queue;
const config = @import("src").parallel.config;

test "work queue initialization" {
    var queue = work_queue.WorkQueue.init(testing.allocator);
    defer queue.deinit();

    try testing.expect(queue.isEmpty());
    try testing.expectEqual(@as(usize, 0), queue.size());
}

test "work queue push and pop" {
    var queue = work_queue.WorkQueue.init(testing.allocator);
    defer queue.deinit();

    const work_item = config.WorkItem.init("test", 1, false);
    try queue.push(work_item);

    try testing.expect(!queue.isEmpty());
    try testing.expectEqual(@as(usize, 1), queue.size());

    const popped = queue.pop();
    try testing.expect(popped != null);
    if (popped) |item| {
        try testing.expectEqualStrings("test", item.chunk);
        try testing.expectEqual(@as(usize, 1), item.chunk_id);
        try testing.expect(!item.is_final);
    }

    try testing.expect(queue.isEmpty());
}

test "work queue batch operations" {
    var queue = work_queue.WorkQueue.init(testing.allocator);
    defer queue.deinit();

    const items = [_]config.WorkItem{
        config.WorkItem.init("item1", 1, false),
        config.WorkItem.init("item2", 2, false),
        config.WorkItem.init("item3", 3, true),
    };

    try queue.pushBatch(&items);
    try testing.expectEqual(@as(usize, 3), queue.size());

    // Pop all items
    for (0..3) |i| {
        const popped = queue.pop();
        try testing.expect(popped != null);
        if (popped) |item| {
            try testing.expectEqual(@as(usize, i + 1), item.chunk_id);
        }
    }

    try testing.expect(queue.isEmpty());
}

test "work queue non-blocking pop" {
    var queue = work_queue.WorkQueue.init(testing.allocator);
    defer queue.deinit();

    // Pop from empty queue should return null
    const empty_pop = queue.popNonBlocking();
    try testing.expect(empty_pop == null);

    // Add item and pop
    const work_item = config.WorkItem.init("test", 1, false);
    try queue.push(work_item);

    const popped = queue.popNonBlocking();
    try testing.expect(popped != null);
    try testing.expect(queue.isEmpty());
}

test "work queue clear" {
    var queue = work_queue.WorkQueue.init(testing.allocator);
    defer queue.deinit();

    const items = [_]config.WorkItem{
        config.WorkItem.init("item1", 1, false),
        config.WorkItem.init("item2", 2, false),
    };

    try queue.pushBatch(&items);
    try testing.expectEqual(@as(usize, 2), queue.size());

    queue.clear();
    try testing.expect(queue.isEmpty());
    try testing.expectEqual(@as(usize, 0), queue.size());
}
