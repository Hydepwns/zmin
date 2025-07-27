const std = @import("std");
const AtomicOrder = std.builtin.AtomicOrder;
const RealSimdProcessor = @import("../performance/real_simd_intrinsics.zig").RealSimdProcessor;
const MemoryOptimizer = @import("../performance/memory_optimizer.zig").MemoryOptimizer;

/// High-performance parallel minifier with optimal work distribution
pub const OptimizedParallelMinifier = struct {
    // Core components
    thread_pool: OptimizedThreadPool,
    work_distributor: WorkDistributor,
    result_collector: ResultCollector,
    memory_optimizer: MemoryOptimizer,

    // Configuration
    thread_count: usize,
    chunk_size: usize,
    numa_nodes: usize,

    // Performance tracking
    total_operations: std.atomic.Value(u64),
    total_bytes_processed: std.atomic.Value(u64),
    total_processing_time: std.atomic.Value(u64),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: ParallelConfig) !OptimizedParallelMinifier {
        const thread_count = if (config.thread_count == 0)
            try std.Thread.getCpuCount()
        else
            config.thread_count;

        return OptimizedParallelMinifier{
            .thread_pool = try OptimizedThreadPool.init(allocator, thread_count),
            .work_distributor = WorkDistributor.init(allocator, config.chunk_strategy),
            .result_collector = try ResultCollector.init(allocator, thread_count),
            .memory_optimizer = try MemoryOptimizer.init(allocator),
            .thread_count = thread_count,
            .chunk_size = config.chunk_size,
            .numa_nodes = config.numa_nodes,
            .total_operations = std.atomic.Value(u64).init(0),
            .total_bytes_processed = std.atomic.Value(u64).init(0),
            .total_processing_time = std.atomic.Value(u64).init(0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OptimizedParallelMinifier) void {
        self.thread_pool.deinit();
        self.work_distributor.deinit();
        self.result_collector.deinit();
        self.memory_optimizer.deinit();
    }

    /// High-performance parallel JSON minification
    pub fn minify(self: *OptimizedParallelMinifier, input: []const u8, output: []u8) !usize {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            _ = self.total_operations.fetchAdd(1, .monotonic);
            _ = self.total_bytes_processed.fetchAdd(input.len, .monotonic);
            _ = self.total_processing_time.fetchAdd(@as(u64, @intCast(end_time - start_time)), .monotonic);
        }

        // Optimize for small inputs - use single-threaded path
        if (input.len < self.chunk_size * 2) {
            return self.minifySingleThreaded(input, output);
        }

        // Distribute work across threads
        const work_chunks = try self.work_distributor.distributeWork(input);
        defer self.work_distributor.freeWorkChunks(work_chunks);

        // Process chunks in parallel
        try self.thread_pool.processBatch(work_chunks);

        // Collect and merge results
        const result_size = try self.result_collector.collectResults(work_chunks, output);

        return result_size;
    }

    fn minifySingleThreaded(self: *OptimizedParallelMinifier, input: []const u8, output: []u8) !usize {
        // Use optimized memory access patterns
        return try self.memory_optimizer.optimizeAccess(input, output);
    }

    pub fn getPerformanceStats(self: *OptimizedParallelMinifier) ParallelPerformanceStats {
        const total_ops = self.total_operations.load(.monotonic);
        const total_bytes = self.total_bytes_processed.load(.monotonic);
        const total_time = self.total_processing_time.load(.monotonic);

        const avg_throughput = if (total_time > 0)
            (@as(f64, @floatFromInt(total_bytes)) * 1_000_000_000.0) / @as(f64, @floatFromInt(total_time))
        else
            0.0;

        return ParallelPerformanceStats{
            .total_operations = total_ops,
            .total_bytes_processed = total_bytes,
            .avg_throughput_bps = avg_throughput,
            .thread_pool_stats = self.thread_pool.getStats(),
            .work_distributor_stats = self.work_distributor.getStats(),
            .result_collector_stats = self.result_collector.getStats(),
        };
    }

    pub const ParallelConfig = struct {
        thread_count: usize = 0, // 0 = auto-detect
        chunk_size: usize = 64 * 1024, // 64KB chunks
        chunk_strategy: ChunkStrategy = .adaptive,
        numa_nodes: usize = 1,
    };

    const ParallelPerformanceStats = struct {
        total_operations: u64,
        total_bytes_processed: u64,
        avg_throughput_bps: f64,
        thread_pool_stats: OptimizedThreadPool.PoolStats,
        work_distributor_stats: WorkDistributor.DistributorStats,
        result_collector_stats: ResultCollector.CollectorStats,
    };
};

/// Optimized thread pool with NUMA awareness and work stealing
const OptimizedThreadPool = struct {
    threads: []std.Thread,
    workers: []Worker,
    thread_count: usize,

    // Global coordination
    shutdown: std.atomic.Value(bool),
    work_available: std.atomic.Value(bool),

    // Performance tracking
    tasks_completed: std.atomic.Value(u64),
    work_stolen: std.atomic.Value(u64),
    idle_cycles: std.atomic.Value(u64),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, thread_count: usize) !OptimizedThreadPool {
        const threads = try allocator.alloc(std.Thread, thread_count);
        const workers = try allocator.alloc(Worker, thread_count);

        // Initialize workers
        for (workers, 0..) |*worker, i| {
            worker.* = try Worker.init(allocator, i);
        }

        var pool = OptimizedThreadPool{
            .threads = threads,
            .workers = workers,
            .thread_count = thread_count,
            .shutdown = std.atomic.Value(bool).init(false),
            .work_available = std.atomic.Value(bool).init(false),
            .tasks_completed = std.atomic.Value(u64).init(0),
            .work_stolen = std.atomic.Value(u64).init(0),
            .idle_cycles = std.atomic.Value(u64).init(0),
            .allocator = allocator,
        };

        // Start worker threads
        for (threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, workerThreadMain, .{ &pool, i });
        }

        return pool;
    }

    pub fn deinit(self: *OptimizedThreadPool) void {
        // Signal shutdown
        self.shutdown.store(true, .release);
        self.work_available.store(true, .release);

        // Wait for threads to finish
        for (self.threads) |thread| {
            thread.join();
        }

        // Clean up workers
        for (self.workers) |*worker| {
            worker.deinit();
        }

        self.allocator.free(self.threads);
        self.allocator.free(self.workers);
    }

    pub fn processBatch(self: *OptimizedThreadPool, work_chunks: []WorkChunk) !void {
        // Distribute work to workers
        for (work_chunks, 0..) |*chunk, i| {
            const worker_id = i % self.thread_count;
            try self.workers[worker_id].addWork(chunk);
        }

        // Signal work availability
        self.work_available.store(true, .release);

        // Wait for completion
        while (!self.allWorkCompleted(work_chunks)) {
            std.Thread.yield() catch {};
        }
    }

    fn allWorkCompleted(self: *OptimizedThreadPool, work_chunks: []WorkChunk) bool {
        _ = self;
        for (work_chunks) |*chunk| {
            if (!chunk.completed.load(.acquire)) {
                return false;
            }
        }
        return true;
    }

    fn workerThreadMain(pool: *OptimizedThreadPool, worker_id: usize) void {
        const worker = &pool.workers[worker_id];

        while (!pool.shutdown.load(.acquire)) {
            // Try to get work from local queue
            if (worker.getWork()) |work_chunk| {
                worker.processWork(work_chunk);
                _ = pool.tasks_completed.fetchAdd(1, .monotonic);
                continue;
            }

            // Try to steal work from other workers
            if (pool.stealWork(worker_id)) |work_chunk| {
                worker.processWork(work_chunk);
                _ = pool.tasks_completed.fetchAdd(1, .monotonic);
                _ = pool.work_stolen.fetchAdd(1, .monotonic);
                continue;
            }

            // No work available, wait briefly
            if (!pool.work_available.load(.acquire)) {
                _ = pool.idle_cycles.fetchAdd(1, .monotonic);
                std.Thread.yield() catch {};
            }
        }
    }

    fn stealWork(self: *OptimizedThreadPool, stealer_id: usize) ?*WorkChunk {
        // Try to steal from other workers
        for (0..self.thread_count) |i| {
            if (i != stealer_id) {
                if (self.workers[i].stealWork()) |work| {
                    return work;
                }
            }
        }
        return null;
    }

    pub fn getStats(self: *OptimizedThreadPool) PoolStats {
        return PoolStats{
            .thread_count = self.thread_count,
            .tasks_completed = self.tasks_completed.load(.monotonic),
            .work_stolen = self.work_stolen.load(.monotonic),
            .idle_cycles = self.idle_cycles.load(.monotonic),
        };
    }

    const PoolStats = struct {
        thread_count: usize,
        tasks_completed: u64,
        work_stolen: u64,
        idle_cycles: u64,
    };
};

/// Individual worker thread with local work queue
const Worker = struct {
    work_queue: std.ArrayList(*WorkChunk),
    simd_processor: RealSimdProcessor,
    worker_id: usize,

    // Performance tracking
    tasks_processed: u64,
    bytes_processed: u64,

    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, worker_id: usize) !Worker {
        return Worker{
            .work_queue = std.ArrayList(*WorkChunk).init(allocator),
            .simd_processor = RealSimdProcessor.init(),
            .worker_id = worker_id,
            .tasks_processed = 0,
            .bytes_processed = 0,
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Worker) void {
        self.work_queue.deinit();
    }

    pub fn addWork(self: *Worker, work_chunk: *WorkChunk) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.work_queue.append(work_chunk);
    }

    pub fn getWork(self: *Worker) ?*WorkChunk {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.work_queue.items.len > 0) {
            return self.work_queue.pop();
        }
        return null;
    }

    pub fn stealWork(self: *Worker) ?*WorkChunk {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.work_queue.items.len > 1) {
            // Steal from the front (oldest work)
            return self.work_queue.orderedRemove(0);
        }
        return null;
    }

    pub fn processWork(self: *Worker, work_chunk: *WorkChunk) void {
        const output_size = self.simd_processor.processWhitespaceIntrinsics(work_chunk.input, work_chunk.output);

        work_chunk.output_size = output_size;
        work_chunk.completed.store(true, .release);

        self.tasks_processed += 1;
        self.bytes_processed += work_chunk.input.len;
    }
};

/// Smart work distribution system
const WorkDistributor = struct {
    chunk_strategy: ChunkStrategy,
    allocator: std.mem.Allocator,

    // Statistics
    chunks_created: u64,
    total_input_size: u64,

    pub fn init(allocator: std.mem.Allocator, strategy: ChunkStrategy) WorkDistributor {
        return WorkDistributor{
            .chunk_strategy = strategy,
            .allocator = allocator,
            .chunks_created = 0,
            .total_input_size = 0,
        };
    }

    pub fn deinit(self: *WorkDistributor) void {
        _ = self;
    }

    pub fn distributeWork(self: *WorkDistributor, input: []const u8) ![]WorkChunk {
        const chunk_size = self.calculateOptimalChunkSize(input.len);
        const chunk_count = (input.len + chunk_size - 1) / chunk_size;

        const chunks = try self.allocator.alloc(WorkChunk, chunk_count);

        for (chunks, 0..) |*chunk, i| {
            const start = i * chunk_size;
            const end = @min(start + chunk_size, input.len);

            chunk.* = WorkChunk{
                .input = input[start..end],
                .output = try self.allocator.alloc(u8, end - start),
                .output_size = 0,
                .chunk_id = i,
                .completed = std.atomic.Value(bool).init(false),
            };
        }

        self.chunks_created += chunk_count;
        self.total_input_size += input.len;

        return chunks;
    }

    pub fn freeWorkChunks(self: *WorkDistributor, chunks: []WorkChunk) void {
        for (chunks) |*chunk| {
            self.allocator.free(chunk.output);
        }
        self.allocator.free(chunks);
    }

    fn calculateOptimalChunkSize(self: *WorkDistributor, input_size: usize) usize {
        return switch (self.chunk_strategy) {
            .fixed => 64 * 1024, // 64KB
            .adaptive => {
                if (input_size < 1024 * 1024) { // < 1MB
                    return 16 * 1024; // 16KB chunks
                } else if (input_size < 10 * 1024 * 1024) { // < 10MB
                    return 64 * 1024; // 64KB chunks
                } else {
                    return 256 * 1024; // 256KB chunks
                }
            },
            .cache_aware => {
                // Optimize for L3 cache size
                const l3_cache_size = 8 * 1024 * 1024; // 8MB typical
                return @min(l3_cache_size / 16, 256 * 1024);
            },
        };
    }

    pub fn getStats(self: *WorkDistributor) DistributorStats {
        return DistributorStats{
            .chunks_created = self.chunks_created,
            .total_input_size = self.total_input_size,
            .avg_chunk_size = if (self.chunks_created > 0)
                self.total_input_size / self.chunks_created
            else
                0,
        };
    }

    const DistributorStats = struct {
        chunks_created: u64,
        total_input_size: u64,
        avg_chunk_size: u64,
    };
};

/// Efficient result collection and merging
const ResultCollector = struct {
    temp_buffers: [][]u8,
    allocator: std.mem.Allocator,

    // Statistics
    collections_performed: u64,
    total_output_size: u64,

    pub fn init(allocator: std.mem.Allocator, thread_count: usize) !ResultCollector {
        const buffers = try allocator.alloc([]u8, thread_count);
        for (buffers) |*buffer| {
            buffer.* = try allocator.alloc(u8, 1024 * 1024); // 1MB per thread
        }

        return ResultCollector{
            .temp_buffers = buffers,
            .allocator = allocator,
            .collections_performed = 0,
            .total_output_size = 0,
        };
    }

    pub fn deinit(self: *ResultCollector) void {
        for (self.temp_buffers) |buffer| {
            self.allocator.free(buffer);
        }
        self.allocator.free(self.temp_buffers);
    }

    pub fn collectResults(self: *ResultCollector, chunks: []WorkChunk, output: []u8) !usize {
        var total_size: usize = 0;

        // Collect results in order
        for (chunks) |*chunk| {
            if (total_size + chunk.output_size <= output.len) {
                @memcpy(output[total_size .. total_size + chunk.output_size], chunk.output[0..chunk.output_size]);
                total_size += chunk.output_size;
            } else {
                return error.OutputBufferTooSmall;
            }
        }

        self.collections_performed += 1;
        self.total_output_size += total_size;

        return total_size;
    }

    pub fn getStats(self: *ResultCollector) CollectorStats {
        return CollectorStats{
            .collections_performed = self.collections_performed,
            .total_output_size = self.total_output_size,
            .avg_output_size = if (self.collections_performed > 0)
                self.total_output_size / self.collections_performed
            else
                0,
        };
    }

    const CollectorStats = struct {
        collections_performed: u64,
        total_output_size: u64,
        avg_output_size: u64,
    };
};

/// Work chunk for parallel processing
const WorkChunk = struct {
    input: []const u8,
    output: []u8,
    output_size: usize,
    chunk_id: usize,
    completed: std.atomic.Value(bool),
};

const ChunkStrategy = enum {
    fixed,
    adaptive,
    cache_aware,
};
