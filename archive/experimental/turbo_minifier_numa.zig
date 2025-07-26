// TURBO Mode with NUMA-aware parallel processing
// Optimizes memory allocation for multi-socket systems

const std = @import("std");
const NumaAllocator = @import("../performance/numa_allocator_v2.zig").NumaAllocator;

pub const TurboMinifierNuma = struct {
    allocator: std.mem.Allocator,
    numa_allocator: NumaAllocator,
    thread_count: usize,
    threads_per_node: usize,
    
    pub const Config = struct {
        thread_count: usize = 0, // 0 = auto
        numa_aware: bool = true,
    };
    
    pub fn init(allocator: std.mem.Allocator, config: Config) !TurboMinifierNuma {
        const thread_count = if (config.thread_count == 0)
            try std.Thread.getCpuCount()
        else
            config.thread_count;
            
        const numa_allocator = NumaAllocator.init(allocator);
        const threads_per_node = if (numa_allocator.numa_available and numa_allocator.node_count > 0)
            thread_count / numa_allocator.node_count
        else
            thread_count;
            
        return TurboMinifierNuma{
            .allocator = allocator,
            .numa_allocator = numa_allocator,
            .thread_count = thread_count,
            .threads_per_node = threads_per_node,
        };
    }
    
    pub fn deinit(self: *TurboMinifierNuma) void {
        self.numa_allocator.deinit();
    }
    
    pub fn minify(self: *TurboMinifierNuma, input: []const u8, output: []u8) !usize {
        // For small inputs, use single thread
        if (input.len < 1024 * 1024 or self.thread_count == 1) {
            return minifyChunk(input, output);
        }
        
        // Get NUMA info
        const info = self.numa_allocator.getInfo();
        _ = info;
        
        // Divide work evenly among threads
        const chunk_size = input.len / self.thread_count;
        
        // Thread context
        
        // Allocate contexts (regular allocation for metadata)
        var contexts = try self.allocator.alloc(ThreadContext, self.thread_count);
        defer self.allocator.free(contexts);
        
        const threads = try self.allocator.alloc(std.Thread, self.thread_count);
        defer self.allocator.free(threads);
        
        // Allocate output buffers on appropriate NUMA nodes
        var temp_buffers = try self.allocator.alloc([]u8, self.thread_count);
        defer {
            for (temp_buffers) |buf| {
                if (buf.len > 0) self.numa_allocator.free(buf);
            }
            self.allocator.free(temp_buffers);
        }
        
        // Initialize contexts and allocate NUMA-aware buffers
        var offset: usize = 0;
        for (0..self.thread_count) |i| {
            const start = offset;
            const end = if (i == self.thread_count - 1) input.len else start + chunk_size;
            const numa_node = self.numa_allocator.getNodeForThread(i);
            
            // Allocate buffer with NUMA hints
            temp_buffers[i] = try self.numa_allocator.allocForThread(u8, end - start, i);
            
            contexts[i] = .{
                .thread_id = i,
                .numa_node = numa_node,
                .input = input[start..end],
                .output = temp_buffers[i],
                .result = 0,
                .err = null,
            };
            
            offset = end;
        }
        
        // Start threads
        for (threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, threadWorker, .{&self.numa_allocator, &contexts[i]});
        }
        
        // Wait for completion
        for (threads) |thread| {
            thread.join();
        }
        
        // Check for errors
        for (contexts) |ctx| {
            if (ctx.err) |err| return err;
        }
        
        // Merge results
        var total: usize = 0;
        for (contexts) |ctx| {
            if (total + ctx.result > output.len) {
                return error.OutputBufferTooSmall;
            }
            @memcpy(output[total..total + ctx.result], ctx.output[0..ctx.result]);
            total += ctx.result;
        }
        
        return total;
    }
    
    fn threadWorker(numa_allocator: *NumaAllocator, ctx: *ThreadContext) void {
        // Set thread affinity to appropriate CPUs
        if (numa_allocator.numa_available) {
            const cpus = numa_allocator.getCpusForNode(ctx.numa_node) catch return;
            defer numa_allocator.base_allocator.free(cpus);
            numa_allocator.setThreadAffinity(cpus) catch {};
        }
        
        ctx.result = minifyChunk(ctx.input, ctx.output) catch |err| {
            ctx.err = err;
            return;
        };
    }
    
    fn minifyChunk(input: []const u8, output: []u8) !usize {
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        // Process in cache-friendly chunks
        const CACHE_LINE = 64;
        const chunk_size = CACHE_LINE * 16; // 1KB chunks
        
        while (i < input.len) {
            const chunk_end = @min(i + chunk_size, input.len);
            
            // Prefetch next chunk
            if (chunk_end < input.len) {
                @prefetch(&input[chunk_end], .{ .rw = .read, .locality = 2 });
            }
            
            while (i < chunk_end) {
                const c = input[i];
                
                if (in_string) {
                    output[out_pos] = c;
                    out_pos += 1;
                    
                    if (c == '\\' and !escaped) {
                        escaped = true;
                    } else if (c == '"' and !escaped) {
                        in_string = false;
                        escaped = false;
                    } else {
                        escaped = false;
                    }
                } else {
                    if (c == '"') {
                        output[out_pos] = c;
                        out_pos += 1;
                        in_string = true;
                    } else if (!isWhitespace(c)) {
                        output[out_pos] = c;
                        out_pos += 1;
                    }
                }
                
                i += 1;
            }
        }
        
        return out_pos;
    }
    
    inline fn isWhitespace(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }
    
    const ThreadContext = struct {
        thread_id: usize,
        numa_node: u32,
        input: []const u8,
        output: []u8,
        result: usize,
        err: ?anyerror,
    };
    
    pub fn getStats(self: *TurboMinifierNuma) Stats {
        const info = self.numa_allocator.getInfo();
        return Stats{
            .numa_available = info.numa_available,
            .node_count = info.node_count,
            .thread_count = self.thread_count,
            .threads_per_node = self.threads_per_node,
        };
    }
    
    pub const Stats = struct {
        numa_available: bool,
        node_count: u32,
        thread_count: usize,
        threads_per_node: usize,
    };
};