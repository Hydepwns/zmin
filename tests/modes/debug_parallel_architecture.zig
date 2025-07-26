// Debug test to understand parallel architecture issues
const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Parallel Architecture Debug\n", .{});
    try stdout.print("===========================\n\n", .{});
    
    // Test basic condition variable behavior
    try stdout.print("Testing condition variables...\n", .{});
    
    var mutex = std.Thread.Mutex{};
    var cond = std.Thread.Condition{};
    var ready = false;
    
    const thread = try std.Thread.spawn(.{}, testWorker, .{&mutex, &cond, &ready});
    
    // Give worker time to start
    std.time.sleep(100_000_000); // 100ms
    
    // Signal the worker
    {
        mutex.lock();
        defer mutex.unlock();
        ready = true;
        cond.signal();
    }
    
    thread.join();
    try stdout.print("Condition variable test passed!\n\n", .{});
    
    // Test the work queue pattern
    try stdout.print("Testing work queue pattern...\n", .{});
    try testWorkQueue();
}

fn testWorker(mutex: *std.Thread.Mutex, cond: *std.Thread.Condition, ready: *bool) void {
    const stdout = std.io.getStdOut().writer();
    
    mutex.lock();
    defer mutex.unlock();
    
    stdout.print("Worker: Waiting for signal...\n", .{}) catch {};
    
    while (!ready.*) {
        cond.wait(mutex);
    }
    
    stdout.print("Worker: Got signal, exiting\n", .{}) catch {};
}

fn testWorkQueue() !void {
    const stdout = std.io.getStdOut().writer();
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Simple work queue
    var mutex = std.Thread.Mutex{};
    var work_available = std.Thread.Condition{};
    var work_done = std.Thread.Condition{};
    var queue = std.ArrayList(i32).init(allocator);
    defer queue.deinit();
    var processed: usize = 0;
    var total_work: usize = 0;
    var shutdown = false;
    
    const Context = struct {
        mutex: *std.Thread.Mutex,
        work_available: *std.Thread.Condition,
        work_done: *std.Thread.Condition,
        queue: *std.ArrayList(i32),
        processed: *usize,
        total_work: *usize,
        shutdown: *bool,
    };
    
    const ctx = Context{
        .mutex = &mutex,
        .work_available = &work_available,
        .work_done = &work_done,
        .queue = &queue,
        .processed = &processed,
        .total_work = &total_work,
        .shutdown = &shutdown,
    };
    
    // Start worker
    const worker = try std.Thread.spawn(.{}, workQueueWorker, .{ctx});
    
    // Submit work
    {
        mutex.lock();
        defer mutex.unlock();
        
        for (0..5) |i| {
            try queue.append(@intCast(i));
        }
        total_work = 5;
        work_available.signal();
    }
    
    // Wait for completion
    {
        mutex.lock();
        defer mutex.unlock();
        
        while (processed < total_work) {
            work_done.wait(&mutex);
        }
    }
    
    try stdout.print("All work completed!\n", .{});
    
    // Shutdown
    {
        mutex.lock();
        defer mutex.unlock();
        shutdown = true;
        work_available.signal();
    }
    
    worker.join();
    try stdout.print("Worker shut down successfully!\n", .{});
}

fn workQueueWorker(ctx: anytype) void {
    const stdout = std.io.getStdOut().writer();
    
    while (true) {
        const work = blk: {
            ctx.mutex.lock();
            defer ctx.mutex.unlock();
            
            while (ctx.queue.items.len == 0 and !ctx.shutdown.*) {
                ctx.work_available.wait(ctx.mutex);
            }
            
            if (ctx.shutdown.*) break :blk null;
            
            break :blk ctx.queue.pop();
        };
        
        if (work) |item| {
            stdout.print("Processing item: {d}\n", .{item}) catch {};
            std.time.sleep(10_000_000); // 10ms
            
            ctx.mutex.lock();
            defer ctx.mutex.unlock();
            ctx.processed.* += 1;
            
            if (ctx.processed.* == ctx.total_work.*) {
                ctx.work_done.signal();
            }
        } else {
            break;
        }
    }
}