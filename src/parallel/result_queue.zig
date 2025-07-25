const std = @import("std");
const config = @import("config.zig");

pub const ResultQueue = struct {
    results: std.ArrayList(config.ChunkResult),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .results = std.ArrayList(config.ChunkResult).init(allocator),
            .mutex = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all result outputs before deallocating the queue
        for (self.results.items) |*result| {
            result.deinit(self.allocator);
        }
        self.results.deinit();
    }

    pub fn push(self: *Self, result: config.ChunkResult) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.results.append(result);
    }

    pub fn pushBatch(self: *Self, results: []const config.ChunkResult) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (results) |result| {
            try self.results.append(result);
        }
    }

    pub fn pop(self: *Self) ?config.ChunkResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.results.items.len > 0) {
            return self.results.orderedRemove(0);
        }
        return null;
    }

    pub fn popAll(self: *Self) []config.ChunkResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        const items = self.results.items;
        const result = self.allocator.alloc(config.ChunkResult, items.len) catch return &[_]config.ChunkResult{};
        @memcpy(result, items);
        self.results.clearRetainingCapacity();
        return result;
    }

    pub fn size(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.results.items.len;
    }

    pub fn isEmpty(self: *Self) bool {
        return self.size() == 0;
    }

    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Free all result outputs
        for (self.results.items) |*result| {
            result.deinit(self.allocator);
        }
        self.results.clearRetainingCapacity();
    }

    pub fn sortByChunkId(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        std.mem.sort(config.ChunkResult, self.results.items, {}, struct {
            fn lessThan(_: void, a: config.ChunkResult, b: config.ChunkResult) bool {
                return a.chunk_id < b.chunk_id;
            }
        }.lessThan);
    }
};
