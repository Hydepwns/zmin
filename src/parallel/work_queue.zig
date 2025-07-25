const std = @import("std");
const config = @import("config.zig");

pub const WorkQueue = struct {
    // Use a fixed-size circular buffer to avoid ArrayList race conditions
    buffer: []config.WorkItem,
    head: usize, // Next position to write
    tail: usize, // Next position to read
    item_count: usize, // Number of items in buffer
    capacity: usize,

    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    allocator: std.mem.Allocator,
    is_shutdown: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const initial_capacity = 64; // Start with reasonable capacity
        const buffer = allocator.alloc(config.WorkItem, initial_capacity) catch {
            // Fallback to empty buffer if allocation fails
            return Self{
                .buffer = &[_]config.WorkItem{},
                .head = 0,
                .tail = 0,
                .item_count = 0,
                .capacity = 0,
                .mutex = .{},
                .condition = .{},
                .allocator = allocator,
                .is_shutdown = false,
            };
        };

        return Self{
            .buffer = buffer,
            .head = 0,
            .tail = 0,
            .item_count = 0,
            .capacity = initial_capacity,
            .mutex = .{},
            .condition = .{},
            .allocator = allocator,
            .is_shutdown = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.shutdown();
        if (self.capacity > 0) {
            self.allocator.free(self.buffer);
        }
    }

    fn ensureCapacity(self: *Self) !void {
        if (self.item_count >= self.capacity) {
            const new_capacity = self.capacity * 2;
            const new_buffer = try self.allocator.alloc(config.WorkItem, new_capacity);

            // Copy existing items to new buffer
            var i: usize = 0;
            while (i < self.item_count) : (i += 1) {
                const index = (self.tail + i) % self.capacity;
                new_buffer[i] = self.buffer[index];
            }

            // Free old buffer and update state
            self.allocator.free(self.buffer);
            self.buffer = new_buffer;
            self.capacity = new_capacity;
            self.head = self.item_count;
            self.tail = 0;
        }
    }

    pub fn push(self: *Self, item: config.WorkItem) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_shutdown) {
            return error.QueueShutdown;
        }

        try self.ensureCapacity();

        self.buffer[self.head] = item;
        self.head = (self.head + 1) % self.capacity;
        self.item_count += 1;

        self.condition.signal();
    }

    pub fn pushBatch(self: *Self, items: []const config.WorkItem) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_shutdown) {
            return error.QueueShutdown;
        }

        for (items) |item| {
            try self.ensureCapacity();
            self.buffer[self.head] = item;
            self.head = (self.head + 1) % self.capacity;
            self.item_count += 1;
        }

        // Signal once after adding all items
        if (items.len > 0) {
            self.condition.signal();
        }
    }

    pub fn pop(self: *Self) ?config.WorkItem {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Wait for items to become available
        while (self.item_count == 0 and !self.is_shutdown) {
            self.condition.wait(&self.mutex);
        }

        if (self.is_shutdown or self.item_count == 0) {
            return null;
        }

        // Additional safety checks
        if (self.capacity == 0 or self.buffer.len == 0) {
            return null;
        }

        // Ensure tail is within bounds
        if (self.tail >= self.capacity or self.tail >= self.buffer.len) {
            std.debug.print("WorkQueue corruption: tail={}, capacity={}, buffer.len={}\n", 
                          .{ self.tail, self.capacity, self.buffer.len });
            return null;
        }

        const item = self.buffer[self.tail];
        self.tail = (self.tail + 1) % self.capacity;
        self.item_count -= 1;

        return item;
    }

    pub fn popNonBlocking(self: *Self) ?config.WorkItem {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.is_shutdown or self.item_count == 0) {
            return null;
        }

        // Additional safety checks
        if (self.capacity == 0 or self.buffer.len == 0) {
            return null;
        }

        // Ensure tail is within bounds
        if (self.tail >= self.capacity or self.tail >= self.buffer.len) {
            std.debug.print("WorkQueue corruption: tail={}, capacity={}, buffer.len={}\n", 
                          .{ self.tail, self.capacity, self.buffer.len });
            return null;
        }

        const item = self.buffer[self.tail];
        self.tail = (self.tail + 1) % self.capacity;
        self.item_count -= 1;

        return item;
    }

    pub fn size(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.item_count;
    }

    pub fn isEmpty(self: *Self) bool {
        return self.size() == 0;
    }

    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.head = 0;
        self.tail = 0;
        self.item_count = 0;
    }

    pub fn shutdown(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.is_shutdown = true;
        self.condition.broadcast();
    }
};
