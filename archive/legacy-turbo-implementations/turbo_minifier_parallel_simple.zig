// Simple parallel JSON minifier without complex synchronization
// Uses a basic thread pool with fixed work distribution

const std = @import("std");

pub const TurboMinifierParallelSimple = struct {
    allocator: std.mem.Allocator,
    thread_count: usize,
    
    pub const Config = struct {
        thread_count: usize = 0, // 0 = auto
    };
    
    pub fn init(allocator: std.mem.Allocator, config: Config) !TurboMinifierParallelSimple {
        const thread_count = if (config.thread_count == 0)
            try std.Thread.getCpuCount()
        else
            config.thread_count;
            
        return TurboMinifierParallelSimple{
            .allocator = allocator,
            .thread_count = thread_count,
        };
    }
    
    pub fn deinit(self: *TurboMinifierParallelSimple) void {
        _ = self;
    }
    
    pub fn minify(self: *TurboMinifierParallelSimple, input: []const u8, output: []u8) !usize {
        // For small inputs, use single thread
        if (input.len < 1024 * 1024 or self.thread_count == 1) {
            return minifyChunk(input, output);
        }
        
        // Divide work evenly among threads
        const chunk_size = input.len / self.thread_count;
        
        // Thread context
        
        var contexts = try self.allocator.alloc(ThreadContext, self.thread_count);
        defer self.allocator.free(contexts);
        
        const threads = try self.allocator.alloc(std.Thread, self.thread_count);
        defer self.allocator.free(threads);
        
        var temp_buffers = try self.allocator.alloc([]u8, self.thread_count);
        defer {
            for (temp_buffers) |buf| {
                if (buf.len > 0) self.allocator.free(buf);
            }
            self.allocator.free(temp_buffers);
        }
        
        // Initialize contexts and buffers
        var offset: usize = 0;
        for (0..self.thread_count) |i| {
            const start = offset;
            const end = if (i == self.thread_count - 1) input.len else start + chunk_size;
            
            temp_buffers[i] = try self.allocator.alloc(u8, end - start);
            
            contexts[i] = .{
                .input = input[start..end],
                .output = temp_buffers[i],
                .result = 0,
                .err = null,
            };
            
            offset = end;
        }
        
        // Start threads
        for (threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, threadWorker, .{&contexts[i]});
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
    
    const ThreadContext = struct {
        input: []const u8,
        output: []u8,
        result: usize,
        err: ?anyerror,
    };
    
    fn threadWorker(ctx: *ThreadContext) void {
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
        
        while (i < input.len) {
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
        
        return out_pos;
    }
    
    inline fn isWhitespace(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }
    
};