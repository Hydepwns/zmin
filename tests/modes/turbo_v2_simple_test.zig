// Simple test to check if TURBO V2 basic functionality works
const std = @import("std");
const TurboMinifierParallelV2 = @import("turbo_minifier_parallel_v2").TurboMinifierParallelV2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    try stdout.print("TURBO V2 Basic Test\n", .{});
    try stdout.print("===================\n\n", .{});
    
    // Small test case
    const input = "{ \"key\" : \"value\" , \"num\" : 123 }";
    const expected = "{\"key\":\"value\",\"num\":123}";
    
    var output = try allocator.alloc(u8, input.len);
    defer allocator.free(output);
    
    // Initialize with minimal config
    const config = TurboMinifierParallelV2.ParallelConfig{
        .thread_count = 2,
        .enable_work_stealing = false,
        .enable_numa = false,
        .adaptive_chunking = false,
    };
    
    try stdout.print("Initializing TURBO V2 with 2 threads...\n", .{});
    
    var minifier = try TurboMinifierParallelV2.init(allocator, config);
    defer minifier.deinit();
    
    try stdout.print("Initialized successfully!\n", .{});
    
    try stdout.print("Input:  \"{s}\"\n", .{input});
    
    const output_len = try minifier.minify(input, output);
    const result = output[0..output_len];
    
    try stdout.print("Output: \"{s}\"\n", .{result});
    try stdout.print("Expected: \"{s}\"\n", .{expected});
    
    if (std.mem.eql(u8, result, expected)) {
        try stdout.print("\n✅ Test PASSED!\n", .{});
    } else {
        try stdout.print("\n❌ Test FAILED!\n", .{});
    }
}