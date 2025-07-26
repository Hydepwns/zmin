// TURBO Mode Parallel - Multi-threaded approach
// Target: Use multiple cores to achieve 2-3 GB/s aggregate throughput

const std = @import("std");
const builtin = @import("builtin");
const cpu_detection = @import("cpu_detection");

pub const TurboMinifierParallel = struct {
    allocator: std.mem.Allocator,
    thread_count: usize,
    
    pub fn init(allocator: std.mem.Allocator) TurboMinifierParallel {
        return .{
            .allocator = allocator,
            .thread_count = std.Thread.getCpuCount() catch 4,
        };
    }
    
    pub fn minify(self: *TurboMinifierParallel, input: []const u8, output: []u8) !usize {
        // For small inputs, use single-threaded approach
        if (input.len < 1024 * 1024) {
            return minifySingleThread(input, output);
        }
        
        // Split work among threads
        const threads_to_use = @min(self.thread_count, input.len / (256 * 1024));
        if (threads_to_use <= 1) {
            return minifySingleThread(input, output);
        }
        
        // First pass: Find string boundaries to enable proper splitting
        const split_points = try self.findSplitPoints(input, threads_to_use);
        defer self.allocator.free(split_points);
        
        // Allocate result buffers for each thread
        var results = try self.allocator.alloc(ThreadResult, threads_to_use);
        defer self.allocator.free(results);
        
        var threads = try self.allocator.alloc(std.Thread, threads_to_use);
        defer self.allocator.free(threads);
        
        // Launch threads
        for (0..threads_to_use) |i| {
            const start = if (i == 0) 0 else split_points[i - 1];
            const end = if (i == threads_to_use - 1) input.len else split_points[i];
            
            results[i] = .{
                .input = input[start..end],
                .output = output[start..end], // Temporary - will compact later
                .output_len = 0,
            };
            
            threads[i] = try std.Thread.spawn(.{}, processChunk, .{&results[i]});
        }
        
        // Wait for all threads
        for (threads) |thread| {
            thread.join();
        }
        
        // Compact results
        var total_output: usize = 0;
        for (results) |result| {
            if (total_output != result.output.ptr - output.ptr) {
                // Need to move this chunk
                std.mem.copyForwards(u8, output[total_output..total_output + result.output_len], result.output[0..result.output_len]);
            }
            total_output += result.output_len;
        }
        
        return total_output;
    }
    
    const ThreadResult = struct {
        input: []const u8,
        output: []u8,
        output_len: usize,
    };
    
    fn processChunk(result: *ThreadResult) void {
        result.output_len = minifySingleThread(result.input, result.output) catch 0;
    }
    
    // Find safe split points (not inside strings)
    fn findSplitPoints(self: *TurboMinifierParallel, input: []const u8, thread_count: usize) ![]usize {
        var points = try self.allocator.alloc(usize, thread_count - 1);
        
        const chunk_size = input.len / thread_count;
        var in_string = false;
        var escaped = false;
        
        for (0..thread_count - 1) |i| {
            var target = (i + 1) * chunk_size;
            
            // Scan forward to find a safe split point
            while (target < input.len) {
                const c = input[target];
                
                if (escaped) {
                    escaped = false;
                } else if (c == '\\' and in_string) {
                    escaped = true;
                } else if (c == '"') {
                    if (!in_string) {
                        // Found start of string - this is a safe split point
                        points[i] = target;
                        break;
                    }
                    in_string = !in_string;
                } else if (!in_string) {
                    // Not in string - safe to split
                    points[i] = target;
                    break;
                }
                
                target += 1;
            }
            
            if (target >= input.len) {
                points[i] = input.len;
            }
        }
        
        return points;
    }
};

// Single-threaded minification
fn minifySingleThread(input: []const u8, output: []u8) !usize {
    var out_pos: usize = 0;
    var i: usize = 0;
    var in_string = false;
    var escaped = false;
    
    while (i < input.len) {
        const c = input[i];
        
        if (escaped) {
            output[out_pos] = c;
            out_pos += 1;
            escaped = false;
        } else if (in_string) {
            output[out_pos] = c;
            out_pos += 1;
            if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                in_string = false;
            }
        } else {
            if (c == '"') {
                output[out_pos] = c;
                out_pos += 1;
                in_string = true;
            } else if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                output[out_pos] = c;
                out_pos += 1;
            }
        }
        i += 1;
    }
    
    return out_pos;
}