const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we set
    // ReleaseFast as preferred for maximum performance.
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create individual modules for the source files
    const minifier_mod = b.createModule(.{
        .root_source_file = b.path("src/minifier/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    const parallel_mod = b.createModule(.{
        .root_source_file = b.path("src/parallel/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Phase 5: Advanced Features modules
    const validation_mod = b.createModule(.{
        .root_source_file = b.path("src/validation/streaming_validator.zig"),
        .target = target,
        .optimize = optimize,
    });

    const schema_mod = b.createModule(.{
        .root_source_file = b.path("src/schema/schema_optimizer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const production_mod = b.createModule(.{
        .root_source_file = b.path("src/production/error_handling.zig"),
        .target = target,
        .optimize = optimize,
    });

    const logging_mod = b.createModule(.{
        .root_source_file = b.path("src/production/logging.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Performance optimization modules
    const performance_mod = b.createModule(.{
        .root_source_file = b.path("src/performance/ultimate_minifier.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cpu_detection_mod = b.createModule(.{
        .root_source_file = b.path("src/performance/cpu_detection.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add the individual modules to the lib module
    lib_mod.addImport("minifier", minifier_mod);
    lib_mod.addImport("parallel", parallel_mod);
    lib_mod.addImport("validation", validation_mod);
    lib_mod.addImport("schema", schema_mod);
    lib_mod.addImport("production", production_mod);
    lib_mod.addImport("logging", logging_mod);
    lib_mod.addImport("performance", performance_mod);
    lib_mod.addImport("cpu_detection", cpu_detection_mod);

    // We will also create a module for our other entry point, 'main_simple.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main_simple.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create a test module for the minifier
    const extended_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/minifier/extended.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create a test module for the parallel minifier
    const parallel_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/parallel/minifier.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create a test module for the simple parallel minifier
    const parallel_simple_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/parallel/simple_minifier.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create a test module for basic minifier functionality
    const basic_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/minifier/basic.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create test modules for parallel components
    const parallel_config_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/parallel/config.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create a test module for performance testing
    const performance_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/performance/benchmarks.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add dependencies to performance test module
    performance_test_mod.addImport("src", lib_mod);
    performance_test_mod.addImport("minifier", minifier_mod);
    performance_test_mod.addImport("parallel", parallel_mod);
    
    // Create modules for parallel v2 dependencies
    const optimized_work_stealing_mod = b.createModule(.{
        .root_source_file = b.path("src/parallel/optimized_work_stealing.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const memory_optimizer_mod = b.createModule(.{
        .root_source_file = b.path("src/performance/memory_optimizer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const parallel_chunk_processor_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/parallel/chunk_processor.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create test modules for integration tests
    const minimal_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration/minimal.zig"),
        .target = target,
        .optimize = optimize,
    });

    const debug_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration/debug.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Memory leak detection test module
    const memory_leak_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/memory_test.zig"),
        .target = target,
        .optimize = .Debug, // Always run memory tests in debug mode
    });

    // API consistency test module
    const api_consistency_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration/api_consistency.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add src directory to module paths for tests
    extended_test_mod.addImport("src", lib_mod);
    parallel_test_mod.addImport("src", lib_mod);
    parallel_simple_test_mod.addImport("src", lib_mod);
    basic_test_mod.addImport("src", lib_mod);
    parallel_config_test_mod.addImport("src", lib_mod);

    parallel_chunk_processor_test_mod.addImport("src", lib_mod);
    minimal_test_mod.addImport("src", lib_mod);
    debug_test_mod.addImport("src", lib_mod);
    memory_leak_test_mod.addImport("src", lib_mod);
    api_consistency_test_mod.addImport("src", lib_mod);

    // Modules can depend on one another using the `std.Build.Module.addImport` function.
    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a
    // file path. In this case, we set up `exe_mod` to import `lib_mod`.
    exe_mod.addImport("zmin_lib", lib_mod);

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zmin",
        .root_module = lib_mod,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "zmin",
        .root_module = exe_mod,
    });

    // Enable SIMD optimizations and disable stripping for better performance
    exe.root_module.strip = false;

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Performance demo executable
    const perf_exe = b.addExecutable(.{
        .name = "performance_demo",
        .root_source_file = b.path("tools/performance_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    perf_exe.root_module.addImport("src", lib_mod);
    b.installArtifact(perf_exe);

    const perf_run_cmd = b.addRunArtifact(perf_exe);
    perf_run_cmd.step.dependOn(b.getInstallStep());

    const perf_run_step = b.step("perf", "Run performance demo");
    perf_run_step.dependOn(&perf_run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const extended_tests = b.addTest(.{
        .root_module = extended_test_mod,
    });
    const run_extended_tests = b.addRunArtifact(extended_tests);

    const parallel_tests = b.addTest(.{
        .root_module = parallel_test_mod,
    });
    const run_parallel_tests = b.addRunArtifact(parallel_tests);

    const parallel_simple_tests = b.addTest(.{
        .root_module = parallel_simple_test_mod,
    });
    const run_parallel_simple_tests = b.addRunArtifact(parallel_simple_tests);

    const basic_tests = b.addTest(.{
        .root_module = basic_test_mod,
    });
    const run_basic_tests = b.addRunArtifact(basic_tests);

    const performance_tests = b.addTest(.{
        .root_module = performance_test_mod,
    });
    const run_performance_tests = b.addRunArtifact(performance_tests);

    // Re-enabled parallel tests after fixes
    const parallel_config_tests = b.addTest(.{
        .root_module = parallel_config_test_mod,
    });
    const run_parallel_config_tests = b.addRunArtifact(parallel_config_tests);

    const parallel_chunk_processor_tests = b.addTest(.{
        .root_module = parallel_chunk_processor_test_mod,
    });
    const run_parallel_chunk_processor_tests = b.addRunArtifact(parallel_chunk_processor_tests);

    const minimal_tests = b.addTest(.{
        .root_module = minimal_test_mod,
    });
    const run_minimal_tests = b.addRunArtifact(minimal_tests);

    const debug_tests = b.addTest(.{
        .root_module = debug_test_mod,
    });
    const run_debug_tests = b.addRunArtifact(debug_tests);

    const memory_leak_tests = b.addTest(.{
        .root_module = memory_leak_test_mod,
    });
    const run_memory_leak_tests = b.addRunArtifact(memory_leak_tests);

    const api_consistency_tests = b.addTest(.{
        .root_module = api_consistency_test_mod,
    });
    const run_api_consistency_tests = b.addRunArtifact(api_consistency_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_extended_tests.step);
    test_step.dependOn(&run_parallel_tests.step);
    test_step.dependOn(&run_parallel_simple_tests.step);
    test_step.dependOn(&run_basic_tests.step);
    test_step.dependOn(&run_performance_tests.step);
    test_step.dependOn(&run_parallel_config_tests.step);

    test_step.dependOn(&run_parallel_chunk_processor_tests.step);
    test_step.dependOn(&run_minimal_tests.step);
    test_step.dependOn(&run_debug_tests.step);
    test_step.dependOn(&run_api_consistency_tests.step);

    // Mode tests
    const mode_tests = b.addTest(.{
        .root_source_file = b.path("tests/modes/all_mode_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Create modes module
    const modes_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const minifier_interface_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/minifier_interface.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Create minifier modules
    const eco_minifier_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/eco_minifier.zig"),
        .target = target,
        .optimize = optimize,
    });
    eco_minifier_mod.addImport("minifier", minifier_mod);
    
    const sport_minifier_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/sport_minifier.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const turbo_minifier_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_mod.addImport("cpu_detection", cpu_detection_mod);
    
    const turbo_minifier_v2_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_v2.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_v2_mod.addImport("cpu_detection", cpu_detection_mod);
    
    minifier_interface_mod.addImport("mod", modes_mod);
    minifier_interface_mod.addImport("minifier", minifier_mod);
    minifier_interface_mod.addImport("eco_minifier", eco_minifier_mod);
    minifier_interface_mod.addImport("sport_minifier", sport_minifier_mod);
    minifier_interface_mod.addImport("turbo_minifier", turbo_minifier_mod);
    
    // Add modules to mode tests
    mode_tests.root_module.addImport("modes", modes_mod);
    mode_tests.root_module.addImport("minifier_interface", minifier_interface_mod);
    mode_tests.root_module.addImport("minifier", minifier_mod);
    const run_mode_tests = b.addRunArtifact(mode_tests);
    test_step.dependOn(&run_mode_tests.step);
    
    // Granular test commands for specific test suites
    const test_minifier_step = b.step("test:minifier", "Run minifier tests");
    test_minifier_step.dependOn(&run_basic_tests.step);
    test_minifier_step.dependOn(&run_extended_tests.step);
    
    const test_modes_step = b.step("test:modes", "Run mode-specific tests");
    test_modes_step.dependOn(&run_mode_tests.step);
    
    // SPORT mode benchmark
    const sport_benchmark = b.addExecutable(.{
        .name = "sport-benchmark",
        .root_source_file = b.path("tests/modes/sport_benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add modules to benchmark
    sport_benchmark.root_module.addImport("modes", modes_mod);
    sport_benchmark.root_module.addImport("minifier_interface", minifier_interface_mod);
    sport_benchmark.root_module.addImport("sport_minifier", sport_minifier_mod);
    
    const run_sport_benchmark = b.addRunArtifact(sport_benchmark);
    const sport_benchmark_step = b.step("benchmark:sport", "Run SPORT mode performance benchmark");
    sport_benchmark_step.dependOn(&run_sport_benchmark.step);
    
    // TURBO mode benchmark
    const turbo_benchmark = b.addExecutable(.{
        .name = "turbo-benchmark",
        .root_source_file = b.path("tests/modes/turbo_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    
    // Add modules to turbo benchmark
    turbo_benchmark.root_module.addImport("modes", modes_mod);
    turbo_benchmark.root_module.addImport("minifier_interface", minifier_interface_mod);
    turbo_benchmark.root_module.addImport("cpu_detection", cpu_detection_mod);
    
    const run_turbo_benchmark = b.addRunArtifact(turbo_benchmark);
    const turbo_benchmark_step = b.step("benchmark:turbo", "Run TURBO mode performance benchmark");
    turbo_benchmark_step.dependOn(&run_turbo_benchmark.step);
    
    // TURBO optimization benchmark
    const turbo_opt_benchmark = b.addExecutable(.{
        .name = "turbo-opt-benchmark",
        .root_source_file = b.path("tests/modes/turbo_optimization_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    
    // Add modules to turbo optimization benchmark
    turbo_opt_benchmark.root_module.addImport("modes", modes_mod);
    turbo_opt_benchmark.root_module.addImport("minifier_interface", minifier_interface_mod);
    turbo_opt_benchmark.root_module.addImport("turbo_minifier", turbo_minifier_mod);
    const turbo_minifier_optimized_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_optimized.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_optimized_mod.addImport("cpu_detection", cpu_detection_mod);
    
    const turbo_minifier_fast_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_fast.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_fast_mod.addImport("cpu_detection", cpu_detection_mod);
    
    const turbo_minifier_v3_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_v3.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_v3_mod.addImport("cpu_detection", cpu_detection_mod);
    
    const turbo_minifier_v4_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_v4.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_v4_mod.addImport("cpu_detection", cpu_detection_mod);
    
    const turbo_minifier_scalar_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_scalar.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_scalar_mod.addImport("cpu_detection", cpu_detection_mod);
    
    const turbo_minifier_streaming_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_streaming.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_streaming_mod.addImport("cpu_detection", cpu_detection_mod);
    
    const turbo_minifier_simple_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_simple.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const turbo_minifier_simd_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_simd_v2.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_simd_mod.addImport("minifier", minifier_mod);
    
    const turbo_minifier_optimized_v2_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_optimized_v2.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_optimized_v2_mod.addImport("cpu_detection", cpu_detection_mod);
    
    const turbo_minifier_mmap_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_mmap.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_mmap_mod.addImport("cpu_detection", cpu_detection_mod);
    
    const turbo_minifier_parallel_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_parallel.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_parallel_mod.addImport("cpu_detection", cpu_detection_mod);
    
    const turbo_minifier_parallel_v2_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_parallel_v2_fixed.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_minifier_parallel_v2_mod.addImport("cpu_detection", cpu_detection_mod);
    turbo_minifier_parallel_v2_mod.addImport("optimized_work_stealing", optimized_work_stealing_mod);
    turbo_minifier_parallel_v2_mod.addImport("memory_optimizer", memory_optimizer_mod);
    
    const turbo_minifier_parallel_v3_mod = b.createModule(.{
        .root_source_file = b.path("src/modes/turbo_minifier_parallel_v3.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    turbo_opt_benchmark.root_module.addImport("turbo_minifier_fast", turbo_minifier_fast_mod);
    turbo_opt_benchmark.root_module.addImport("turbo_minifier_optimized", turbo_minifier_optimized_mod);
    turbo_opt_benchmark.root_module.addImport("turbo_minifier_v3", turbo_minifier_v3_mod);
    
    // V3 scaling test
    const v3_scaling_test = b.addExecutable(.{
        .name = "v3-scaling",
        .root_source_file = b.path("tests/modes/v3_scaling_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    v3_scaling_test.root_module.addImport("turbo_minifier_v3", turbo_minifier_v3_mod);
    
    const run_v3_scaling = b.addRunArtifact(v3_scaling_test);
    const v3_scaling_step = b.step("profile:v3", "Profile TURBO V3 scaling");
    v3_scaling_step.dependOn(&run_v3_scaling.step);
    
    // Debug benchmark data test
    const debug_benchmark_data = b.addExecutable(.{
        .name = "debug-benchmark-data",
        .root_source_file = b.path("tests/modes/debug_benchmark_data.zig"),
        .target = target,
        .optimize = optimize,
    });
    debug_benchmark_data.root_module.addImport("turbo_minifier_v3", turbo_minifier_v3_mod);
    debug_benchmark_data.root_module.addImport("turbo_minifier_v4", turbo_minifier_v4_mod);
    
    const run_debug_benchmark = b.addRunArtifact(debug_benchmark_data);
    const debug_benchmark_step = b.step("debug:benchmark", "Debug benchmark data patterns");
    debug_benchmark_step.dependOn(&run_debug_benchmark.step);
    
    // V4 test
    const v4_test = b.addExecutable(.{
        .name = "v4-test",
        .root_source_file = b.path("tests/modes/v4_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    v4_test.root_module.addImport("turbo_minifier_v4", turbo_minifier_v4_mod);
    
    const run_v4_test = b.addRunArtifact(v4_test);
    const v4_test_step = b.step("test:v4", "Test TURBO V4 maximum bandwidth");
    v4_test_step.dependOn(&run_v4_test.step);
    
    // Scalar test
    const scalar_test = b.addExecutable(.{
        .name = "scalar-test",
        .root_source_file = b.path("tests/modes/scalar_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    scalar_test.root_module.addImport("turbo_minifier_scalar", turbo_minifier_scalar_mod);
    scalar_test.root_module.addImport("turbo_minifier_v3", turbo_minifier_v3_mod);
    
    const run_scalar_test = b.addRunArtifact(scalar_test);
    const scalar_test_step = b.step("test:scalar", "Test TURBO scalar vs SIMD approaches");
    scalar_test_step.dependOn(&run_scalar_test.step);
    
    // Streaming test
    const streaming_test = b.addExecutable(.{
        .name = "streaming-test",
        .root_source_file = b.path("tests/modes/streaming_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    streaming_test.root_module.addImport("turbo_minifier_streaming", turbo_minifier_streaming_mod);
    streaming_test.root_module.addImport("turbo_minifier_scalar", turbo_minifier_scalar_mod);
    
    const run_streaming_test = b.addRunArtifact(streaming_test);
    const streaming_test_step = b.step("test:streaming", "Test TURBO streaming bulk operations");
    streaming_test_step.dependOn(&run_streaming_test.step);
    
    // Phase 2 test
    const phase2_test = b.addExecutable(.{
        .name = "phase2-test",
        .root_source_file = b.path("tests/modes/phase2_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    phase2_test.root_module.addImport("turbo_minifier_simple", turbo_minifier_simple_mod);
    phase2_test.root_module.addImport("turbo_minifier_scalar", turbo_minifier_scalar_mod);
    
    const run_phase2_test = b.addRunArtifact(phase2_test);
    const phase2_test_step = b.step("test:phase2", "Test TURBO Phase 2 optimizations");
    phase2_test_step.dependOn(&run_phase2_test.step);
    
    // Optimization investigation test
    const opt_test = b.addExecutable(.{
        .name = "opt-test",
        .root_source_file = b.path("tests/modes/optimization_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    opt_test.root_module.addImport("turbo_minifier_scalar", turbo_minifier_scalar_mod);
    
    const run_opt_test = b.addRunArtifact(opt_test);
    const opt_test_step = b.step("test:opt", "Investigate optimization bottlenecks");
    opt_test_step.dependOn(&run_opt_test.step);
    
    // V2 optimization test
    const v2_opt_test = b.addExecutable(.{
        .name = "v2-opt-test",
        .root_source_file = b.path("tests/modes/v2_opt_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    v2_opt_test.root_module.addImport("turbo_minifier_optimized_v2", turbo_minifier_optimized_v2_mod);
    v2_opt_test.root_module.addImport("turbo_minifier_scalar", turbo_minifier_scalar_mod);
    
    const run_v2_opt_test = b.addRunArtifact(v2_opt_test);
    const v2_opt_test_step = b.step("test:v2opt", "Test V2 optimizations");
    v2_opt_test_step.dependOn(&run_v2_opt_test.step);
    
    // Final comprehensive test
    const final_test = b.addExecutable(.{
        .name = "final-test",
        .root_source_file = b.path("tests/modes/final_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    final_test.root_module.addImport("turbo_minifier_scalar", turbo_minifier_scalar_mod);
    final_test.root_module.addImport("turbo_minifier_mmap", turbo_minifier_mmap_mod);
    final_test.root_module.addImport("turbo_minifier_parallel", turbo_minifier_parallel_mod);
    
    const run_final_test = b.addRunArtifact(final_test);
    const final_test_step = b.step("test:final", "Final comprehensive performance test");
    final_test_step.dependOn(&run_final_test.step);
    
    const run_turbo_opt_benchmark = b.addRunArtifact(turbo_opt_benchmark);
    const turbo_opt_benchmark_step = b.step("benchmark:turbo-opt", "Run TURBO mode optimization benchmark");
    turbo_opt_benchmark_step.dependOn(&run_turbo_opt_benchmark.step);
    
    // TURBO Parallel V2 benchmark
    const turbo_parallel_v2_benchmark = b.addExecutable(.{
        .name = "turbo-parallel-v2-benchmark",
        .root_source_file = b.path("tests/modes/turbo_parallel_v2_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    turbo_parallel_v2_benchmark.root_module.addImport("turbo_minifier_parallel_v2", turbo_minifier_parallel_v2_mod);
    turbo_parallel_v2_benchmark.root_module.addImport("turbo_minifier_simple", turbo_minifier_simple_mod);
    
    const run_turbo_parallel_v2_benchmark = b.addRunArtifact(turbo_parallel_v2_benchmark);
    const turbo_parallel_v2_benchmark_step = b.step("benchmark:turbo-v2", "Run TURBO Parallel V2 performance benchmark");
    turbo_parallel_v2_benchmark_step.dependOn(&run_turbo_parallel_v2_benchmark.step);
    
    // TURBO Parallel V2 quick validation
    const turbo_v2_quick = b.addExecutable(.{
        .name = "turbo-v2-quick",
        .root_source_file = b.path("tests/modes/turbo_v2_quick_bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    turbo_v2_quick.root_module.addImport("turbo_minifier_parallel_v2", turbo_minifier_parallel_v2_mod);
    turbo_v2_quick.root_module.addImport("turbo_minifier_simple", turbo_minifier_simple_mod);
    
    const run_turbo_v2_quick = b.addRunArtifact(turbo_v2_quick);
    const turbo_v2_quick_step = b.step("benchmark:v2-quick", "Quick validation of TURBO V2 performance");
    turbo_v2_quick_step.dependOn(&run_turbo_v2_quick.step);
    
    // TURBO V2 simple test
    const turbo_v2_simple_test = b.addExecutable(.{
        .name = "turbo-v2-simple-test",
        .root_source_file = b.path("tests/modes/turbo_v2_simple_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_v2_simple_test.root_module.addImport("turbo_minifier_parallel_v2", turbo_minifier_parallel_v2_mod);
    
    const run_turbo_v2_simple_test = b.addRunArtifact(turbo_v2_simple_test);
    const turbo_v2_simple_test_step = b.step("test:v2-simple", "Test basic TURBO V2 functionality");
    turbo_v2_simple_test_step.dependOn(&run_turbo_v2_simple_test.step);
    
    // TURBO V2 performance test
    const turbo_v2_perf_test = b.addExecutable(.{
        .name = "turbo-v2-perf-test",
        .root_source_file = b.path("tests/modes/turbo_v2_perf_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    turbo_v2_perf_test.root_module.addImport("turbo_minifier_parallel_v2", turbo_minifier_parallel_v2_mod);
    
    const run_turbo_v2_perf_test = b.addRunArtifact(turbo_v2_perf_test);
    const turbo_v2_perf_test_step = b.step("test:v2-perf", "Test TURBO V2 performance");
    turbo_v2_perf_test_step.dependOn(&run_turbo_v2_perf_test.step);
    
    // TURBO V2 debug test
    const turbo_v2_debug = b.addExecutable(.{
        .name = "turbo-v2-debug",
        .root_source_file = b.path("tests/modes/turbo_v2_debug.zig"),
        .target = target,
        .optimize = optimize,
    });
    turbo_v2_debug.root_module.addImport("turbo_minifier_parallel_v2", turbo_minifier_parallel_v2_mod);
    
    const run_turbo_v2_debug = b.addRunArtifact(turbo_v2_debug);
    const turbo_v2_debug_step = b.step("test:v2-debug", "Debug TURBO V2 issues");
    turbo_v2_debug_step.dependOn(&run_turbo_v2_debug.step);
    
    // TURBO V2 simple debug test
    const turbo_v2_debug_simple = b.addExecutable(.{
        .name = "turbo-v2-debug-simple",
        .root_source_file = b.path("tests/modes/turbo_v2_debug_simple.zig"),
        .target = target,
        .optimize = .Debug,
    });
    turbo_v2_debug_simple.root_module.addImport("turbo_minifier_parallel_v2", turbo_minifier_parallel_v2_mod);
    
    const run_turbo_v2_debug_simple = b.addRunArtifact(turbo_v2_debug_simple);
    const turbo_v2_debug_simple_step = b.step("test:v2-debug-simple", "Simple debug test for TURBO V2");
    turbo_v2_debug_simple_step.dependOn(&run_turbo_v2_debug_simple.step);
    
    // TURBO V2 final benchmark
    const turbo_v2_final = b.addExecutable(.{
        .name = "turbo-v2-final",
        .root_source_file = b.path("tests/modes/turbo_v2_final_bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    turbo_v2_final.root_module.addImport("turbo_minifier_parallel_v2", turbo_minifier_parallel_v2_mod);
    turbo_v2_final.root_module.addImport("turbo_minifier_simple", turbo_minifier_simple_mod);
    
    const run_turbo_v2_final = b.addRunArtifact(turbo_v2_final);
    const turbo_v2_final_step = b.step("benchmark:v2-final", "Final TURBO V2 performance validation");
    turbo_v2_final_step.dependOn(&run_turbo_v2_final.step);
    
    // TURBO SIMD benchmark
    const turbo_simd_benchmark = b.addExecutable(.{
        .name = "turbo-simd-benchmark",
        .root_source_file = b.path("tests/modes/turbo_simd_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    turbo_simd_benchmark.root_module.addImport("turbo_minifier_simd", turbo_minifier_simd_mod);
    turbo_simd_benchmark.root_module.addImport("turbo_minifier_simple", turbo_minifier_simple_mod);
    
    const run_turbo_simd_benchmark = b.addRunArtifact(turbo_simd_benchmark);
    const turbo_simd_benchmark_step = b.step("benchmark:simd", "Benchmark SIMD whitespace detection");
    turbo_simd_benchmark_step.dependOn(&run_turbo_simd_benchmark.step);
    
    // TURBO V3 test
    const turbo_v3_test = b.addExecutable(.{
        .name = "turbo-v3-test",
        .root_source_file = b.path("tests/modes/turbo_v3_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    turbo_v3_test.root_module.addImport("turbo_minifier_parallel_v3", turbo_minifier_parallel_v3_mod);
    turbo_v3_test.root_module.addImport("turbo_minifier_simple", turbo_minifier_simple_mod);
    
    const run_turbo_v3_test = b.addRunArtifact(turbo_v3_test);
    const turbo_v3_test_step = b.step("test:v3", "Test TURBO V3 parallel implementation");
    turbo_v3_test_step.dependOn(&run_turbo_v3_test.step);
    
    // Debug parallel architecture
    const debug_parallel = b.addExecutable(.{
        .name = "debug-parallel",
        .root_source_file = b.path("tests/modes/debug_parallel_architecture.zig"),
        .target = target,
        .optimize = .Debug,
    });
    
    const run_debug_parallel = b.addRunArtifact(debug_parallel);
    const debug_parallel_step = b.step("debug:parallel", "Debug parallel architecture");
    debug_parallel_step.dependOn(&run_debug_parallel.step);
    
    // TURBO profiling tool
    const turbo_profile = b.addExecutable(.{
        .name = "turbo-profile",
        .root_source_file = b.path("tests/modes/turbo_profile.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    
    turbo_profile.root_module.addImport("turbo_minifier", turbo_minifier_mod);
    
    const run_turbo_profile = b.addRunArtifact(turbo_profile);
    const turbo_profile_step = b.step("profile:turbo", "Profile TURBO mode performance");
    turbo_profile_step.dependOn(&run_turbo_profile.step);

    const test_parallel_step = b.step("test:parallel", "Run parallel processing tests");
    test_parallel_step.dependOn(&run_parallel_tests.step);
    test_parallel_step.dependOn(&run_parallel_simple_tests.step);
    test_parallel_step.dependOn(&run_parallel_config_tests.step);

    test_parallel_step.dependOn(&run_parallel_chunk_processor_tests.step);

    const test_performance_step = b.step("test:performance", "Run performance tests");
    test_performance_step.dependOn(&run_performance_tests.step);

    const test_integration_step = b.step("test:integration", "Run integration tests");
    test_integration_step.dependOn(&run_minimal_tests.step);
    test_integration_step.dependOn(&run_debug_tests.step);
    test_integration_step.dependOn(&run_api_consistency_tests.step);

    // Fast tests (excluding performance tests)
    const test_fast_step = b.step("test:fast", "Run fast tests (excludes performance)");
    test_fast_step.dependOn(&run_lib_unit_tests.step);
    test_fast_step.dependOn(&run_exe_unit_tests.step);
    test_fast_step.dependOn(&run_basic_tests.step);
    test_fast_step.dependOn(&run_extended_tests.step);
    test_fast_step.dependOn(&run_parallel_config_tests.step);

    test_fast_step.dependOn(&run_minimal_tests.step);
    test_fast_step.dependOn(&run_debug_tests.step);
    test_fast_step.dependOn(&run_api_consistency_tests.step);

    // Slow tests (performance and heavy parallel tests)
    const test_slow_step = b.step("test:slow", "Run slow tests (performance and stress tests)");
    test_slow_step.dependOn(&run_performance_tests.step);
    test_slow_step.dependOn(&run_parallel_tests.step);
    test_slow_step.dependOn(&run_parallel_simple_tests.step);
    test_slow_step.dependOn(&run_parallel_chunk_processor_tests.step);

    // Test coverage reporting
    const coverage_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    coverage_tests.setExecCmd(&.{
        "kcov", "--exclude-pattern=/usr", "zig-out/coverage", "--",
    });
    const run_coverage_tests = b.addRunArtifact(coverage_tests);
    const coverage_step = b.step("test:coverage", "Run tests with coverage reporting");
    coverage_step.dependOn(&run_coverage_tests.step);

    // Memory leak detection tests
    const memory_test_step = b.step("test:memory", "Run tests with memory leak detection");
    memory_test_step.dependOn(&run_memory_leak_tests.step);

    // CI-friendly test runner with JSON output
    const ci_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_ci_tests = b.addRunArtifact(ci_tests);
    run_ci_tests.addArg("--summary-report");
    const ci_step = b.step("test:ci", "Run tests with CI-friendly output");
    ci_step.dependOn(&run_ci_tests.step);

    // Add CI/CD Tools
    const performance_monitor_exe = b.addExecutable(.{
        .name = "performance-monitor",
        .root_source_file = b.path("tools/performance_monitor.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(performance_monitor_exe);

    const badge_generator_exe = b.addExecutable(.{
        .name = "badge-generator",
        .root_source_file = b.path("tools/generate_badges.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(badge_generator_exe);

    // Add CI/CD tool steps
    const run_performance_monitor = b.addRunArtifact(performance_monitor_exe);
    const performance_monitor_step = b.step("tools:performance-monitor", "Parse benchmark output and generate performance data");
    performance_monitor_step.dependOn(&run_performance_monitor.step);

    const run_badge_generator = b.addRunArtifact(badge_generator_exe);
    const badge_generator_step = b.step("tools:badges", "Generate performance badges");
    badge_generator_step.dependOn(&run_badge_generator.step);

    // Add comprehensive CI pipeline step
    const ci_pipeline_step = b.step("ci:pipeline", "Run complete CI pipeline: build, test, benchmark, and generate badges");
    ci_pipeline_step.dependOn(&run_cmd.step);
    ci_pipeline_step.dependOn(&run_lib_unit_tests.step);
    ci_pipeline_step.dependOn(&run_exe_unit_tests.step);
    ci_pipeline_step.dependOn(&run_extended_tests.step);
    ci_pipeline_step.dependOn(&run_parallel_tests.step);
    ci_pipeline_step.dependOn(&run_parallel_simple_tests.step);
    ci_pipeline_step.dependOn(&run_basic_tests.step);
    ci_pipeline_step.dependOn(&run_performance_tests.step);

    ci_pipeline_step.dependOn(&run_badge_generator.step);
}
