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

    // Add the individual modules to the lib module
    lib_mod.addImport("minifier", minifier_mod);
    lib_mod.addImport("parallel", parallel_mod);

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
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

    const parallel_work_queue_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/parallel/work_queue.zig"),
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
    parallel_work_queue_test_mod.addImport("src", lib_mod);
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

    const parallel_work_queue_tests = b.addTest(.{
        .root_module = parallel_work_queue_test_mod,
    });
    const run_parallel_work_queue_tests = b.addRunArtifact(parallel_work_queue_tests);

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
    test_step.dependOn(&run_parallel_work_queue_tests.step);
    test_step.dependOn(&run_parallel_chunk_processor_tests.step);
    test_step.dependOn(&run_minimal_tests.step);
    test_step.dependOn(&run_debug_tests.step);
    test_step.dependOn(&run_api_consistency_tests.step);

    // Granular test commands for specific test suites
    const test_minifier_step = b.step("test:minifier", "Run minifier tests");
    test_minifier_step.dependOn(&run_basic_tests.step);
    test_minifier_step.dependOn(&run_extended_tests.step);

    const test_parallel_step = b.step("test:parallel", "Run parallel processing tests");
    test_parallel_step.dependOn(&run_parallel_tests.step);
    test_parallel_step.dependOn(&run_parallel_simple_tests.step);
    test_parallel_step.dependOn(&run_parallel_config_tests.step);
    test_parallel_step.dependOn(&run_parallel_work_queue_tests.step);
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
    test_fast_step.dependOn(&run_parallel_work_queue_tests.step);
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
}
