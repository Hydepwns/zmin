const std = @import("std");
const types = @import("types.zig");

pub fn createModules(b: *std.Build, config: types.Config) types.ModuleRegistry {
    // Core library module
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    // Executable module
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main_simple.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    // Core functionality modules
    const minifier_mod = b.createModule(.{
        .root_source_file = b.path("src/minifier/mod.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const parallel_mod = b.createModule(.{
        .root_source_file = b.path("src/parallel/mod.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const modes_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/mod.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    // Advanced features modules
    const validation_mod = b.createModule(.{
        .root_source_file = b.path("src/validation/streaming_validator.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const schema_mod = b.createModule(.{
        .root_source_file = b.path("src/schema/schema_optimizer.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const production_mod = b.createModule(.{
        .root_source_file = b.path("src/production/error_handling.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const logging_mod = b.createModule(.{
        .root_source_file = b.path("src/production/logging.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    // Performance modules
    const performance_mod = b.createModule(.{
        .root_source_file = b.path("src/performance/ultimate_minifier.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const cpu_detection_mod = b.createModule(.{
        .root_source_file = b.path("src/performance/cpu_detection.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    // Minifier interface
    const minifier_interface_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/minifier_interface.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    // Mode-specific minifiers
    const eco_minifier_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/eco_minifier.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const sport_minifier_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/sport_minifier.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const turbo_unified_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo/mod.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    // Performance and parallel optimization modules
    const optimized_work_stealing_mod = b.createModule(.{
        .root_source_file = b.path("src/parallel/optimized_work_stealing.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const memory_optimizer_mod = b.createModule(.{
        .root_source_file = b.path("src/performance/memory_optimizer.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    // Phase 2: New performance and reliability modules
    const numa_detector_mod = b.createModule(.{
        .root_source_file = b.path("src/performance/numa_detector.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const memory_profiler_mod = b.createModule(.{
        .root_source_file = b.path("src/performance/memory_profiler.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const core_errors_mod = b.createModule(.{
        .root_source_file = b.path("src/core/errors.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    const error_recovery_mod = b.createModule(.{
        .root_source_file = b.path("src/core/error_recovery.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    return types.ModuleRegistry{
        .lib_mod = lib_mod,
        .exe_mod = exe_mod,
        .minifier_mod = minifier_mod,
        .parallel_mod = parallel_mod,
        .modes_mod = modes_mod,
        .cpu_detection_mod = cpu_detection_mod,
        .validation_mod = validation_mod,
        .schema_mod = schema_mod,
        .production_mod = production_mod,
        .logging_mod = logging_mod,
        .performance_mod = performance_mod,
        .minifier_interface_mod = minifier_interface_mod,
        .eco_minifier_mod = eco_minifier_mod,
        .sport_minifier_mod = sport_minifier_mod,
        .turbo_unified_mod = turbo_unified_mod,
        .optimized_work_stealing_mod = optimized_work_stealing_mod,
        .memory_optimizer_mod = memory_optimizer_mod,
        .numa_detector_mod = numa_detector_mod,
        .memory_profiler_mod = memory_profiler_mod,
        .core_errors_mod = core_errors_mod,
        .error_recovery_mod = error_recovery_mod,
    };
}
