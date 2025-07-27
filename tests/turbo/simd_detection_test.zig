const std = @import("std");
const testing = std.testing;
const interface = @import("../../src/modes/turbo/core/interface.zig");

test "SIMD feature detection works" {
    const caps = try interface.SystemCapabilities.detect();
    
    // Test that we can detect SIMD features
    const simd = caps.simd_features;
    
    // On x86_64, we should at least have SSE2
    const builtin = @import("builtin");
    if (builtin.cpu.arch == .x86_64) {
        // Modern x86_64 CPUs always have SSE2
        try testing.expect(simd.sse2);
    }
    
    // Test helper methods
    if (simd.hasAnySimd()) {
        const desc = simd.getDescription();
        try testing.expect(desc.len > 0);
        try testing.expect(!std.mem.eql(u8, desc, "None"));
    }
    
    // Test getBestLevel
    const level = simd.getBestLevel();
    if (simd.hasAnySimd()) {
        try testing.expect(level != null);
        try testing.expectEqual(level.?, .simd);
    }
}

test "SimdFeatures methods work correctly" {
    // Test with no features
    const no_simd = interface.SimdFeatures{};
    try testing.expect(!no_simd.hasAnySimd());
    try testing.expectEqual(no_simd.getBestLevel(), null);
    try testing.expectEqualStrings(no_simd.getDescription(), "None");
    
    // Test with SSE2
    const sse2_only = interface.SimdFeatures{ .sse2 = true };
    try testing.expect(sse2_only.hasAnySimd());
    try testing.expectEqual(sse2_only.getBestLevel().?, .simd);
    try testing.expectEqualStrings(sse2_only.getDescription(), "SSE2");
    
    // Test with AVX2
    const avx2 = interface.SimdFeatures{ 
        .sse = true,
        .sse2 = true,
        .avx = true,
        .avx2 = true,
    };
    try testing.expect(avx2.hasAnySimd());
    try testing.expectEqual(avx2.getBestLevel().?, .simd);
    try testing.expectEqualStrings(avx2.getDescription(), "AVX2");
    
    // Test with AVX-512
    const avx512 = interface.SimdFeatures{ 
        .sse = true,
        .sse2 = true,
        .avx = true,
        .avx2 = true,
        .avx512 = true,
    };
    try testing.expect(avx512.hasAnySimd());
    try testing.expectEqual(avx512.getBestLevel().?, .simd);
    try testing.expectEqualStrings(avx512.getDescription(), "AVX-512");
}

test "SystemCapabilities detects reasonable values" {
    const caps = try interface.SystemCapabilities.detect();
    
    // Should have at least 1 CPU core
    try testing.expect(caps.cpu_cores >= 1);
    
    // Should have some memory
    try testing.expect(caps.available_memory > 0);
    
    // Should have at least 1 NUMA node
    try testing.expect(caps.numa_nodes >= 1);
    
    // Log the detected capabilities for debugging
    std.debug.print("\nDetected System Capabilities:\n", .{});
    std.debug.print("  CPU Cores: {}\n", .{caps.cpu_cores});
    std.debug.print("  Memory: {} MB\n", .{caps.available_memory / (1024 * 1024)});
    std.debug.print("  NUMA Nodes: {}\n", .{caps.numa_nodes});
    std.debug.print("  SIMD: {s}\n", .{caps.simd_features.getDescription()});
}