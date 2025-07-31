const std = @import("std");

// Build configuration structure
pub const Config = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

// Module registry for centralized module management
pub const ModuleRegistry = struct {
    lib_mod: *std.Build.Module,
    exe_mod: *std.Build.Module,
    minifier_mod: *std.Build.Module,
    parallel_mod: *std.Build.Module,
    modes_mod: *std.Build.Module,
    cpu_detection_mod: *std.Build.Module,

    // Core modules
    validation_mod: *std.Build.Module,
    schema_mod: *std.Build.Module,
    production_mod: *std.Build.Module,
    logging_mod: *std.Build.Module,
    performance_mod: *std.Build.Module,
    minifier_interface_mod: *std.Build.Module,

    // Mode minifiers
    eco_minifier_mod: *std.Build.Module,
    sport_minifier_mod: *std.Build.Module,
    turbo_unified_mod: *std.Build.Module,

    // Performance and parallel modules
    optimized_work_stealing_mod: *std.Build.Module,
    memory_optimizer_mod: *std.Build.Module,
    numa_detector_mod: *std.Build.Module,
    memory_profiler_mod: *std.Build.Module,

    // Error handling modules
    core_errors_mod: *std.Build.Module,
    error_recovery_mod: *std.Build.Module,
    
    // Common utilities
    common_mod: *std.Build.Module,
};
