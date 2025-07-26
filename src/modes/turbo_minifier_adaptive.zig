// TURBO Mode with adaptive chunk sizing for optimal performance
const std = @import("std");
const AdaptiveChunking = @import("../performance/adaptive_chunking.zig").AdaptiveChunking;

pub const TurboMinifierAdaptive = struct {
    allocator: std.mem.Allocator,
    thread_count: usize,
    
    pub const Config = struct {
        thread_count: usize = 0, // 0 = auto-detect
        force_chunk_size: ?usize = null, // Override adaptive sizing
    };
    
    pub fn init(allocator: std.mem.Allocator, config: Config) !TurboMinifierAdaptive {
        const thread_count = if (config.thread_count == 0)
            try std.Thread.getCpuCount()
        else
            config.thread_count;
            
        return TurboMinifierAdaptive{
            .allocator = allocator,
            .thread_count = thread_count,
        };
    }
    
    pub fn deinit(self: *TurboMinifierAdaptive) void {
        _ = self;
    }
    
    pub fn minify(self: *TurboMinifierAdaptive, input: []const u8, output: []u8) !usize {
        return self.minifyWithConfig(input, output, .{});
    }
    
    pub fn minifyWithConfig(self: *TurboMinifierAdaptive, input: []const u8, output: []u8, config: Config) !usize {
        // For small inputs or single thread, use direct processing
        if (input.len < 64 * 1024 or self.thread_count == 1) {
            return minifyChunk(input, output);
        }
        
        // Calculate optimal chunk size
        const chunk_size = if (config.force_chunk_size) |forced|
            forced
        else
            AdaptiveChunking.calculateOptimalChunkSize(input.len, self.thread_count);
        
        const chunk_count = AdaptiveChunking.calculateChunkCount(input.len, self.thread_count, chunk_size);
        const actual_threads = @min(self.thread_count, chunk_count);
        
        // Create processing context
        
        // Allocate chunk info
        var chunks = try self.allocator.alloc(ChunkInfo, chunk_count);
        defer self.allocator.free(chunks);
        
        // Allocate output buffers for each chunk
        var temp_buffers = try self.allocator.alloc([]u8, chunk_count);
        defer {
            for (temp_buffers) |buf| {
                if (buf.len > 0) self.allocator.free(buf);
            }
            self.allocator.free(temp_buffers);
        }
        
        // Initialize chunks with adaptive sizing
        var offset: usize = 0;
        for (0..chunk_count) |i| {
            const start = offset;
            const end = @min(start + chunk_size, input.len);
            
            // Ensure we don't have empty chunks
            if (start >= input.len) break;
            
            temp_buffers[i] = try self.allocator.alloc(u8, end - start);
            
            chunks[i] = .{
                .id = i,
                .input_slice = input[start..end],
                .output_buffer = temp_buffers[i],
                .result_size = 0,
                .thread_id = i % actual_threads,
            };
            
            offset = end;
        }
        
        // Process chunks in parallel with work distribution
        try self.processChunksParallel(chunks[0..@min(chunk_count, chunks.len)], actual_threads);
        
        // Merge results
        var total_output: usize = 0;
        for (chunks[0..@min(chunk_count, chunks.len)]) |chunk| {
            if (chunk.result_size == 0) continue; // Skip empty chunks
            
            if (total_output + chunk.result_size > output.len) {
                return error.OutputBufferTooSmall;
            }
            
            @memcpy(output[total_output..total_output + chunk.result_size], 
                   chunk.output_buffer[0..chunk.result_size]);
            total_output += chunk.result_size;
        }
        
        return total_output;
    }
    
    fn processChunksParallel(self: *TurboMinifierAdaptive, chunks: []ChunkInfo, thread_count: usize) !void {
        if (thread_count == 1) {
            // Single-threaded processing
            for (chunks) |*chunk| {
                chunk.result_size = try minifyChunk(chunk.input_slice, chunk.output_buffer);
            }
            return;
        }
        
        // Multi-threaded processing with work stealing
        
        var work_context = LocalWorkContext{
            .chunks = chunks,
            .next_chunk = std.atomic.Value(usize).init(0),
            .error_occurred = std.atomic.Value(bool).init(false),
        };
        
        const threads = try self.allocator.alloc(std.Thread, thread_count);
        defer self.allocator.free(threads);
        
        // Start worker threads
        for (threads) |*thread| {
            thread.* = try std.Thread.spawn(.{}, workerThread, .{&work_context});
        }
        
        // Wait for completion
        for (threads) |thread| {
            thread.join();
        }
        
        if (work_context.error_occurred.load(.acquire)) {
            return error.ProcessingError;
        }
    }
    
    fn workerThread(context: *anyopaque) void {
        const work_context: *LocalWorkContext = @ptrCast(@alignCast(context));
        
        while (true) {
            // Get next chunk to process
            const chunk_index = work_context.next_chunk.fetchAdd(1, .acquire);
            if (chunk_index >= work_context.chunks.len) break;
            
            // Process chunk
            const chunk = &work_context.chunks[chunk_index];
            chunk.result_size = minifyChunk(chunk.input_slice, chunk.output_buffer) catch {
                work_context.error_occurred.store(true, .release);
                return;
            };
        }
    }
    
    fn minifyChunk(input: []const u8, output: []u8) !usize {
        var out_pos: usize = 0;
        var i: usize = 0;
        var in_string = false;
        var escaped = false;
        
        // Optimized processing with unrolling for hot path
        while (i < input.len) {
            const c = input[i];
            
            if (in_string) {
                // In string: copy character and handle escaping
                if (out_pos >= output.len) return error.OutputBufferTooSmall;
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
                // Outside string: handle whitespace removal
                if (c == '"') {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                    in_string = true;
                } else if (!isWhitespace(c)) {
                    if (out_pos >= output.len) return error.OutputBufferTooSmall;
                    output[out_pos] = c;
                    out_pos += 1;
                }
            }
            
            i += 1;
        }
        
        return out_pos;
    }
    
    inline fn isWhitespace(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }
    
    // Get performance info for current configuration
    pub fn getPerformanceInfo(self: *TurboMinifierAdaptive, file_size: usize) PerformanceInfo {
        const chunk_size = AdaptiveChunking.calculateOptimalChunkSize(file_size, self.thread_count);
        const estimate = AdaptiveChunking.getPerformanceEstimate(file_size, self.thread_count, chunk_size);
        
        return PerformanceInfo{
            .optimal_chunk_size = chunk_size,
            .estimated_throughput = estimate.estimated_throughput_mb_s,
            .chunk_efficiency = estimate.chunk_efficiency,
            .thread_efficiency = estimate.thread_efficiency,
            .is_optimal_config = estimate.recommended,
        };
    }
    
    const ChunkInfo = struct {
        id: usize,
        input_slice: []const u8,
        output_buffer: []u8,
        result_size: usize,
        thread_id: usize,
    };
    
    const LocalWorkContext = struct {
        chunks: []ChunkInfo,
        next_chunk: std.atomic.Value(usize),
        error_occurred: std.atomic.Value(bool),
    };
    
    pub const PerformanceInfo = struct {
        optimal_chunk_size: usize,
        estimated_throughput: f64,
        chunk_efficiency: f64,
        thread_efficiency: f64,
        is_optimal_config: bool,
    };
};