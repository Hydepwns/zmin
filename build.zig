const std = @import("std");

// Build configuration structure
const Config = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

// Module registry for centralized module management
const ModuleRegistry = struct {
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
};

pub fn build(b: *std.Build) void {
    const config = Config{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{
            .preferred_optimize_mode = .ReleaseFast,
        }),
    };

    // Create all modules
    const modules = createModules(b, config);

    // Setup module dependencies
    setupModuleDependencies(modules);

    // Create library and executable
    _ = createLibrary(b, modules);
    const exe = createExecutable(b, modules);

    // Create test suite
    createTestSuite(b, config, modules);

    // Create benchmarks and tools
    createBenchmarks(b, config, modules);
    createTools(b, config, modules);

    // Setup build steps
    setupBuildSteps(b, exe);
}

fn createModules(b: *std.Build, config: Config) ModuleRegistry {
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

    return ModuleRegistry{
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

fn setupModuleDependencies(modules: ModuleRegistry) void {
    // Setup core module dependencies
    modules.lib_mod.addImport("minifier", modules.minifier_mod);
    modules.lib_mod.addImport("parallel", modules.parallel_mod);
    modules.lib_mod.addImport("validation", modules.validation_mod);
    modules.lib_mod.addImport("schema", modules.schema_mod);
    modules.lib_mod.addImport("production", modules.production_mod);
    modules.lib_mod.addImport("logging", modules.logging_mod);
    modules.lib_mod.addImport("performance", modules.performance_mod);
    modules.lib_mod.addImport("cpu_detection", modules.cpu_detection_mod);

    // Setup executable dependencies
    modules.exe_mod.addImport("zmin_lib", modules.lib_mod);

    // Setup mode dependencies
    modules.eco_minifier_mod.addImport("minifier", modules.minifier_mod);
    modules.sport_minifier_mod.addImport("minifier", modules.minifier_mod);
    modules.turbo_unified_mod.addImport("cpu_detection", modules.cpu_detection_mod);
    modules.turbo_unified_mod.addImport("numa_detector", modules.numa_detector_mod);
    
    // Setup error handling dependencies
    modules.error_recovery_mod.addImport("errors", modules.core_errors_mod);
    modules.error_recovery_mod.addImport("modes", modules.modes_mod);
    
    // Add new modules to lib
    modules.lib_mod.addImport("numa_detector", modules.numa_detector_mod);
    modules.lib_mod.addImport("memory_profiler", modules.memory_profiler_mod);
    modules.lib_mod.addImport("errors", modules.core_errors_mod);
    modules.lib_mod.addImport("error_recovery", modules.error_recovery_mod);

    // Setup minifier interface dependencies
    modules.minifier_interface_mod.addImport("mod", modules.modes_mod);
    modules.minifier_interface_mod.addImport("minifier", modules.minifier_mod);
    modules.minifier_interface_mod.addImport("eco_minifier", modules.eco_minifier_mod);
    modules.minifier_interface_mod.addImport("sport_minifier", modules.sport_minifier_mod);
    modules.minifier_interface_mod.addImport("turbo_unified", modules.turbo_unified_mod);
}

fn createLibrary(b: *std.Build, modules: ModuleRegistry) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zmin",
        .root_module = modules.lib_mod,
    });

    b.installArtifact(lib);
    return lib;
}

fn createExecutable(b: *std.Build, modules: ModuleRegistry) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "zmin",
        .root_module = modules.exe_mod,
    });

    exe.root_module.strip = false;
    b.installArtifact(exe);
    return exe;
}

fn createTestSuite(b: *std.Build, config: Config, modules: ModuleRegistry) void {
    // Create basic test modules
    const basic_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/minifier/basic.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    basic_test_mod.addImport("src", modules.lib_mod);

    const extended_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/minifier/extended.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    extended_test_mod.addImport("src", modules.lib_mod);

    // Create parallel test modules
    const parallel_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/parallel/minifier.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    parallel_test_mod.addImport("src", modules.lib_mod);

    const parallel_config_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/parallel/config.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    parallel_config_test_mod.addImport("src", modules.lib_mod);

    // Create integration test modules
    const minimal_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration/minimal.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    minimal_test_mod.addImport("src", modules.lib_mod);

    const api_consistency_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration/api_consistency.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    api_consistency_test_mod.addImport("src", modules.lib_mod);

    // Create mode tests
    const mode_tests = b.addTest(.{
        .root_source_file = b.path("tests/modes/all_mode_tests.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    mode_tests.root_module.addImport("modes", modules.modes_mod);
    mode_tests.root_module.addImport("minifier_interface", modules.minifier_interface_mod);
    mode_tests.root_module.addImport("minifier", modules.minifier_mod);

    // Create test steps
    const lib_unit_tests = b.addTest(.{ .root_module = modules.lib_mod });
    const exe_unit_tests = b.addTest(.{ .root_module = modules.exe_mod });
    const basic_tests = b.addTest(.{ .root_module = basic_test_mod });
    const extended_tests = b.addTest(.{ .root_module = extended_test_mod });
    const parallel_tests = b.addTest(.{ .root_module = parallel_test_mod });
    const parallel_config_tests = b.addTest(.{ .root_module = parallel_config_test_mod });
    const minimal_tests = b.addTest(.{ .root_module = minimal_test_mod });
    const api_consistency_tests = b.addTest(.{ .root_module = api_consistency_test_mod });

    // Create run steps
    const run_lib_tests = b.addRunArtifact(lib_unit_tests);
    const run_exe_tests = b.addRunArtifact(exe_unit_tests);
    const run_basic_tests = b.addRunArtifact(basic_tests);
    const run_extended_tests = b.addRunArtifact(extended_tests);
    const run_parallel_tests = b.addRunArtifact(parallel_tests);
    const run_parallel_config_tests = b.addRunArtifact(parallel_config_tests);
    const run_minimal_tests = b.addRunArtifact(minimal_tests);
    const run_api_consistency_tests = b.addRunArtifact(api_consistency_tests);
    const run_mode_tests = b.addRunArtifact(mode_tests);

    // Create test step groups
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_basic_tests.step);
    test_step.dependOn(&run_extended_tests.step);
    test_step.dependOn(&run_parallel_tests.step);
    test_step.dependOn(&run_parallel_config_tests.step);
    test_step.dependOn(&run_minimal_tests.step);
    test_step.dependOn(&run_api_consistency_tests.step);
    test_step.dependOn(&run_mode_tests.step);

    // Fast tests (excludes performance tests)
    const test_fast_step = b.step("test:fast", "Run fast tests (excludes performance)");
    test_fast_step.dependOn(&run_lib_tests.step);
    test_fast_step.dependOn(&run_exe_tests.step);
    test_fast_step.dependOn(&run_basic_tests.step);
    test_fast_step.dependOn(&run_extended_tests.step);
    test_fast_step.dependOn(&run_minimal_tests.step);
    test_fast_step.dependOn(&run_api_consistency_tests.step);

    // Granular test commands
    const test_minifier_step = b.step("test:minifier", "Run minifier tests");
    test_minifier_step.dependOn(&run_basic_tests.step);
    test_minifier_step.dependOn(&run_extended_tests.step);

    const test_modes_step = b.step("test:modes", "Run mode-specific tests");
    test_modes_step.dependOn(&run_mode_tests.step);

    const test_parallel_step = b.step("test:parallel", "Run parallel processing tests");
    test_parallel_step.dependOn(&run_parallel_tests.step);
    test_parallel_step.dependOn(&run_parallel_config_tests.step);

    const test_integration_step = b.step("test:integration", "Run integration tests");
    test_integration_step.dependOn(&run_minimal_tests.step);
    test_integration_step.dependOn(&run_api_consistency_tests.step);
}

fn createBenchmarks(b: *std.Build, config: Config, modules: ModuleRegistry) void {
    // SPORT mode benchmark
    const sport_benchmark = b.addExecutable(.{
        .name = "sport-benchmark",
        .root_source_file = b.path("tests/modes/sport_benchmark.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    sport_benchmark.root_module.addImport("modes", modules.modes_mod);
    sport_benchmark.root_module.addImport("minifier_interface", modules.minifier_interface_mod);
    sport_benchmark.root_module.addImport("sport_minifier", modules.sport_minifier_mod);

    const run_sport_benchmark = b.addRunArtifact(sport_benchmark);
    const sport_benchmark_step = b.step("benchmark:sport", "Run SPORT mode performance benchmark");
    sport_benchmark_step.dependOn(&run_sport_benchmark.step);

    // TURBO mode benchmark
    const turbo_benchmark = b.addExecutable(.{
        .name = "turbo-benchmark",
        .root_source_file = b.path("tests/modes/turbo_benchmark.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
    });
    turbo_benchmark.root_module.addImport("modes", modules.modes_mod);
    turbo_benchmark.root_module.addImport("minifier_interface", modules.minifier_interface_mod);
    turbo_benchmark.root_module.addImport("cpu_detection", modules.cpu_detection_mod);

    const run_turbo_benchmark = b.addRunArtifact(turbo_benchmark);
    const turbo_benchmark_step = b.step("benchmark:turbo", "Run TURBO mode performance benchmark");
    turbo_benchmark_step.dependOn(&run_turbo_benchmark.step);

    // SIMD benchmark
    const simd_benchmark = b.addExecutable(.{
        .name = "simd-benchmark",
        .root_source_file = b.path("tests/modes/turbo_simd_benchmark.zig"),
        .target = config.target,
        .optimize = .ReleaseFast,
    });
    simd_benchmark.root_module.addImport("turbo_unified", modules.turbo_unified_mod);

    const run_simd_benchmark = b.addRunArtifact(simd_benchmark);
    const simd_benchmark_step = b.step("benchmark:simd", "Benchmark SIMD whitespace detection");
    simd_benchmark_step.dependOn(&run_simd_benchmark.step);
}

fn createTools(b: *std.Build, config: Config, modules: ModuleRegistry) void {
    // Performance demo
    const perf_exe = b.addExecutable(.{
        .name = "performance_demo",
        .root_source_file = b.path("tools/performance_demo.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    perf_exe.root_module.addImport("src", modules.lib_mod);
    b.installArtifact(perf_exe);

    const perf_run_cmd = b.addRunArtifact(perf_exe);
    perf_run_cmd.step.dependOn(b.getInstallStep());
    const perf_run_step = b.step("perf", "Run performance demo");
    perf_run_step.dependOn(&perf_run_cmd.step);

    // CI/CD Tools
    const performance_monitor_exe = b.addExecutable(.{
        .name = "performance-monitor",
        .root_source_file = b.path("tools/performance_monitor.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    b.installArtifact(performance_monitor_exe);

    const badge_generator_exe = b.addExecutable(.{
        .name = "badge-generator",
        .root_source_file = b.path("tools/generate_badges.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    b.installArtifact(badge_generator_exe);

    // Tool steps
    const run_performance_monitor = b.addRunArtifact(performance_monitor_exe);
    const performance_monitor_step = b.step("tools:performance-monitor", "Parse benchmark output and generate performance data");
    performance_monitor_step.dependOn(&run_performance_monitor.step);

    const run_badge_generator = b.addRunArtifact(badge_generator_exe);
    const badge_generator_step = b.step("tools:badges", "Generate performance badges");
    badge_generator_step.dependOn(&run_badge_generator.step);
}

fn setupBuildSteps(b: *std.Build, exe: *std.Build.Step.Compile) void {
    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}