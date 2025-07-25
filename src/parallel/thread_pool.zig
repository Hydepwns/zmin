const std = @import("std");
const config = @import("config.zig");

pub const ThreadPool = struct {
    threads: ?[]std.Thread,
    should_stop: bool,
    stop_mutex: std.Thread.Mutex,
    is_started: bool,
    thread_count: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, thread_count: usize, worker_fn: anytype, context: anytype) !Self {
        if (thread_count == 0) {
            return config.ParallelError.ThreadPoolInitFailed;
        }

        var pool = Self{
            .threads = null,
            .should_stop = false,
            .stop_mutex = .{},
            .is_started = false,
            .thread_count = thread_count,
            .allocator = allocator,
        };

        // Create and start threads immediately
        pool.threads = try pool.allocator.alloc(std.Thread, thread_count);

        // Spawn worker threads
        for (0..thread_count) |i| {
            pool.threads.?[i] = try std.Thread.spawn(.{}, worker_fn, .{ context, i });
        }

        pool.is_started = true;

        return pool;
    }

    pub fn stop(self: *Self) void {
        self.stop_mutex.lock();
        defer self.stop_mutex.unlock();
        self.should_stop = true;
    }

    pub fn deinit(self: *Self) void {
        // Signal threads to stop
        self.stop();

        // Wait for all threads to complete
        if (self.threads) |threads| {
            for (threads) |thread| {
                thread.join();
            }
            self.allocator.free(threads);
        }
    }

    pub fn shouldStop(self: *Self) bool {
        self.stop_mutex.lock();
        defer self.stop_mutex.unlock();
        return self.should_stop;
    }

    pub fn isStarted(self: *Self) bool {
        self.stop_mutex.lock();
        defer self.stop_mutex.unlock();
        return self.is_started;
    }

    pub fn getThreadCount(self: *Self) usize {
        return self.thread_count;
    }

    pub fn isRunning(self: *Self) bool {
        return self.isStarted() and !self.shouldStop();
    }
};
