// Test GPU-accelerated minifier
const std = @import("std");
const GPUMinifier = @import("src/gpu/gpu_minifier.zig").GPUMinifier;
const TurboMinifierAdaptive = @import("src/modes/turbo_minifier_adaptive.zig").TurboMinifierAdaptive;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n🚀 GPU Acceleration Test\n", .{});
    try stdout.print("========================\n\n", .{});

    // Initialize GPU minifier
    var gpu_minifier = try GPUMinifier.init(allocator);
    defer gpu_minifier.deinit();

    // Show GPU capabilities
    const gpu_info = gpu_minifier.getGPUInfo();
    try stdout.print("GPU Detection:\n", .{});
    try stdout.print("  Available: {}\n", .{gpu_info.available});
    try stdout.print("  Type: {}\n", .{gpu_info.gpu_type});
    try stdout.print("  Memory: {d} MB\n", .{gpu_info.memory_mb});
    try stdout.print("  Compute Units: {d}\n", .{gpu_info.compute_units});
    try stdout.print("  Device: {s}\n", .{gpu_info.device_name});
    try stdout.print("  Min File Size: {d} MB\n\n", .{gpu_info.min_file_size_mb});

    // Test different file sizes
    const test_sizes = [_]struct { size: usize, name: []const u8 }{
        .{ .size = 10 * 1024 * 1024, .name = "10 MB" },
        .{ .size = 50 * 1024 * 1024, .name = "50 MB" },
        .{ .size = 100 * 1024 * 1024, .name = "100 MB" },
        .{ .size = 200 * 1024 * 1024, .name = "200 MB" },
    };

    for (test_sizes) |test_case| {
        try stdout.print("🧪 Testing {s} file:\n", .{test_case.name});

        const input = try generateTestJson(allocator, test_case.size);
        defer allocator.free(input);

        const output_gpu = try allocator.alloc(u8, input.len);
        defer allocator.free(output_gpu);
        const output_cpu = try allocator.alloc(u8, input.len);
        defer allocator.free(output_cpu);

        // Test GPU implementation
        const gpu_start = std.time.nanoTimestamp();
        const gpu_len = try gpu_minifier.minify(input, output_gpu);
        const gpu_end = std.time.nanoTimestamp();
        const gpu_ns = @as(u64, @intCast(gpu_end - gpu_start));
        const gpu_ms = gpu_ns / 1_000_000;
        const gpu_throughput = if (gpu_ms > 0)
            (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(gpu_ms)) * 1000.0 / (1024.0 * 1024.0))
        else
            0.0;

        // Test adaptive CPU for comparison
        var cpu_adaptive = try TurboMinifierAdaptive.init(allocator, .{});
        defer cpu_adaptive.deinit();

        const cpu_start = std.time.nanoTimestamp();
        const cpu_len = try cpu_adaptive.minify(input, output_cpu);
        const cpu_end = std.time.nanoTimestamp();
        const cpu_ns = @as(u64, @intCast(cpu_end - cpu_start));
        const cpu_ms = cpu_ns / 1_000_000;
        const cpu_throughput = if (cpu_ms > 0)
            (@as(f64, @floatFromInt(test_case.size)) / @as(f64, @floatFromInt(cpu_ms)) * 1000.0 / (1024.0 * 1024.0))
        else
            0.0;

        const speedup = if (cpu_throughput > 0) (gpu_throughput / cpu_throughput) else 0.0;
        const match = (gpu_len == cpu_len);

        try stdout.print("  GPU:         {d:>7.1} MB/s ({d:>4} ms)\n", .{ gpu_throughput, gpu_ms });
        try stdout.print("  CPU Adaptive:{d:>7.1} MB/s ({d:>4} ms)\n", .{ cpu_throughput, cpu_ms });
        try stdout.print("  Speedup:     {d:>7.2}x {s}\n", .{ speedup, if (match) "✅" else "❌" });

        // Show break-even analysis
        const transfer_cost_ms = estimateTransferCost(test_case.size);
        const net_benefit = @as(f64, @floatFromInt(cpu_ms)) - @as(f64, @floatFromInt(gpu_ms)) - transfer_cost_ms;

        try stdout.print("  Transfer Est: {d:.1} ms\n", .{transfer_cost_ms});
        try stdout.print("  Net Benefit:  {d:>7.1} ms ", .{net_benefit});
        if (net_benefit > 0) {
            try stdout.print("(GPU beneficial)\n", .{});
        } else {
            try stdout.print("(CPU better)\n", .{});
        }

        try stdout.print("\n", .{});
    }

    // Show GPU adoption recommendations
    try showGPURecommendations(gpu_info);
}

fn generateTestJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("{\n");

    var key_counter: usize = 0;
    while (buffer.items.len < target_size - 100) {
        if (key_counter > 0) {
            try buffer.appendSlice(",\n");
        }

        const pattern = key_counter % 6;
        switch (pattern) {
            0 => try buffer.writer().print("  \"key_{d}\"  :  \"value with    lots of    whitespace\"", .{key_counter}),
            1 => try buffer.writer().print("  \"data_{d}\" : {{   \"num\" :   {d},   \"str\" : \"test with spaces\"   }}", .{ key_counter, key_counter * 42 }),
            2 => try buffer.writer().print("  \"array_{d}\" : [  1,   2,    3,     4,      5,      6  ]", .{key_counter}),
            3 => try buffer.writer().print("  \"nested_{d}\" : {{  \"a\" : {{  \"b\" :  \"c with   spaces\"  }}  }}", .{key_counter}),
            4 => try buffer.writer().print("  \"long_string_{d}\" : \"This is a much longer string with lots of content and whitespace that should compress well on GPU\"", .{key_counter}),
            5 => try buffer.writer().print("  \"whitespace_heavy_{d}\" : [     \"item1\"    ,    \"item2\"    ,    \"item3\"     ]", .{key_counter}),
            else => unreachable,
        }

        key_counter += 1;
    }

    try buffer.appendSlice("\n}");
    return buffer.toOwnedSlice();
}

fn estimateTransferCost(file_size: usize) f64 {
    // Estimate PCIe transfer cost (both directions)
    const pcie_bandwidth_gb_s = 16.0; // PCIe 4.0 x16
    const transfer_size_gb = @as(f64, @floatFromInt(file_size * 2)) / (1024.0 * 1024.0 * 1024.0); // Input + Output

    return (transfer_size_gb / pcie_bandwidth_gb_s) * 1000.0; // Convert to ms
}

fn showGPURecommendations(gpu_info: anytype) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("💡 GPU Recommendations:\n", .{});
    try stdout.print("========================\n", .{});

    if (!gpu_info.available) {
        try stdout.print("❌ No GPU detected\n", .{});
        try stdout.print("   - Install NVIDIA drivers for CUDA support\n", .{});
        try stdout.print("   - Install OpenCL for cross-platform support\n", .{});
        return;
    }

    try stdout.print("✅ GPU Available: {s}\n", .{gpu_info.device_name});

    switch (gpu_info.gpu_type) {
        .nvidia_cuda => {
            try stdout.print("🚀 NVIDIA GPU detected - Excellent for compute!\n", .{});
            try stdout.print("   - Use for files >{d} MB\n", .{gpu_info.min_file_size_mb});
            try stdout.print("   - Expected 2-5x speedup on large files\n", .{});
            try stdout.print("   - Consider CUDA development for maximum performance\n", .{});
        },
        .generic_opencl => {
            try stdout.print("🔧 OpenCL GPU detected - Good for cross-platform\n", .{});
            try stdout.print("   - Use for files >{d} MB\n", .{gpu_info.min_file_size_mb});
            try stdout.print("   - Expected 1.5-3x speedup on large files\n", .{});
        },
        else => {
            try stdout.print("ℹ️  Basic GPU support available\n", .{});
        },
    }

    try stdout.print("\n🎯 Optimization Targets:\n", .{});

    if (gpu_info.memory_mb >= 8192) {
        try stdout.print("   ✅ High VRAM ({d} MB) - Can handle very large files\n", .{gpu_info.memory_mb});
    } else if (gpu_info.memory_mb >= 4096) {
        try stdout.print("   ⚠️  Medium VRAM ({d} MB) - Good for most files\n", .{gpu_info.memory_mb});
    } else {
        try stdout.print("   ⚠️  Low VRAM ({d} MB) - Limited to smaller files\n", .{gpu_info.memory_mb});
    }

    if (gpu_info.compute_units >= 2000) {
        try stdout.print("   ✅ High compute ({d} units) - Excellent parallelism\n", .{gpu_info.compute_units});
    } else {
        try stdout.print("   ⚠️  Moderate compute ({d} units) - Limited parallelism\n", .{gpu_info.compute_units});
    }
}
