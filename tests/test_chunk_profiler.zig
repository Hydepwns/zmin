// Test chunk size profiler
const std = @import("std");
const ChunkSizeProfiler = @import("src/benchmarks/chunk_size_profiler.zig").ChunkSizeProfiler;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var profiler = ChunkSizeProfiler.init(allocator);
    defer profiler.deinit();
    
    try profiler.profileChunkSizes();
}