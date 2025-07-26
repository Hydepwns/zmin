// Comprehensive mode testing suite

const std = @import("std");
const testing = std.testing;

// Import all mode test modules
const consistency_tests = @import("consistency_tests.zig");
const performance_tests = @import("performance_tests.zig");

// Re-export all tests
test {
    // Run consistency tests
    _ = consistency_tests;
    
    // Run performance tests
    _ = performance_tests;
}

test "mode system initialization" {
    const modes = @import("modes");
    _ = @import("minifier_interface").MinifierInterface;
    
    // Verify all modes are properly defined
    const all_modes = [_]modes.ProcessingMode{ .eco, .sport, .turbo };
    
    for (all_modes) |mode| {
        // Check mode description
        const desc = mode.getDescription();
        try testing.expect(desc.len > 0);
        
        // Check memory usage calculation
        const mem_1mb = mode.getMemoryUsage(1024 * 1024);
        const mem_1gb = mode.getMemoryUsage(1024 * 1024 * 1024);
        
        switch (mode) {
            .eco => {
                try testing.expectEqual(@as(usize, 64 * 1024), mem_1mb);
                try testing.expectEqual(@as(usize, 64 * 1024), mem_1gb);
            },
            .sport => {
                // SPORT mode uses sqrt scaling with 16MB cap
                const expected_1mb = @min(@as(usize, @intFromFloat(std.math.sqrt(1024.0 * 1024.0))), 16 * 1024 * 1024);
                const expected_1gb = @min(@as(usize, @intFromFloat(std.math.sqrt(1024.0 * 1024.0 * 1024.0))), 16 * 1024 * 1024);
                try testing.expectEqual(expected_1mb, mem_1mb);
                try testing.expectEqual(expected_1gb, mem_1gb);
            },
            .turbo => {
                try testing.expectEqual(@as(usize, 1024 * 1024), mem_1mb);
                try testing.expectEqual(@as(usize, 1024 * 1024 * 1024), mem_1gb);
            },
        }
    }
}

test "mode configuration" {
    const modes = @import("modes");
    
    // Test ECO config
    const eco_config = modes.ModeConfig.fromMode(.eco);
    try testing.expectEqual(@as(usize, 64 * 1024), eco_config.chunk_size);
    try testing.expectEqual(false, eco_config.enable_simd);
    try testing.expectEqual(@as(usize, 1), eco_config.parallel_chunks);
    
    // Test SPORT config
    const sport_config = modes.ModeConfig.fromMode(.sport);
    try testing.expectEqual(@as(usize, 1024 * 1024), sport_config.chunk_size);
    try testing.expectEqual(true, sport_config.enable_simd);
    try testing.expectEqual(@as(usize, 4), sport_config.parallel_chunks);
    
    // Test TURBO config
    const turbo_config = modes.ModeConfig.fromMode(.turbo);
    try testing.expectEqual(std.math.maxInt(usize), turbo_config.chunk_size);
    try testing.expectEqual(true, turbo_config.enable_simd);
    try testing.expect(turbo_config.parallel_chunks >= 1);
}

test "platform support detection" {
    const MinifierInterface = @import("minifier_interface").MinifierInterface;
    
    // ECO mode should always be supported
    try testing.expect(MinifierInterface.isModeSupported(.eco));
    
    // SPORT mode should always be supported (has fallback)
    try testing.expect(MinifierInterface.isModeSupported(.sport));
    
    // TURBO mode depends on platform
    const builtin = @import("builtin");
    const turbo_supported = switch (builtin.cpu.arch) {
        .x86_64 => std.Target.x86.featureSetHas(builtin.cpu.features, .sse2),
        .aarch64 => true, // NEON is mandatory
        else => false,
    };
    
    try testing.expectEqual(turbo_supported, MinifierInterface.isModeSupported(.turbo));
}