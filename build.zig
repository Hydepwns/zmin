const std = @import("std");

// Import modular build components
const types = @import("build/types.zig");
const modules = @import("build/modules.zig");
const dependencies = @import("build/dependencies.zig");
const targets = @import("build/targets.zig");
const tests = @import("build/tests.zig");
const benchmarks = @import("build/benchmarks.zig");
const tools = @import("build/tools.zig");

pub fn build(b: *std.Build) void {
    const config = types.Config{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{
            .preferred_optimize_mode = .ReleaseFast,
        }),
    };

    // Add configuration options
    _ = b.option([]const u8, "config", "Configuration file");
    _ = b.option([]const u8, "features", "Enable features");

    // Create all modules
    const module_registry = modules.createModules(b, config);

    // Setup module dependencies
    dependencies.setupModuleDependencies(module_registry);

    // Create library and executable
    _ = targets.createLibrary(b, module_registry);
    const exe = targets.createExecutable(b, module_registry);

    // Create test suite
    tests.createTestSuite(b, config, module_registry);

    // Create benchmarks and tools
    benchmarks.createBenchmarks(b, config, module_registry);
    tools.createTools(b, config, module_registry);

    // Setup build steps
    setupBuildSteps(b, exe, module_registry);

    // Add clean step
    const clean_step = b.step("clean", "Clean build artifacts");
    const clean_cmd = b.addSystemCommand(&.{ "rm", "-rf", "zig-out", ".zig-cache" });
    clean_step.dependOn(&clean_cmd.step);
}

fn setupBuildSteps(b: *std.Build, exe: *std.Build.Step.Compile, module_registry: types.ModuleRegistry) void {
    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Build examples step
    const examples_step = b.step("examples", "Build all examples");

    const example_files = [_][]const u8{
        "examples/basic_usage.zig",
        "examples/mode_selection.zig",
        "examples/streaming.zig",
        "examples/parallel_batch.zig",
        "examples/v2_parallel_example.zig",
        "examples/v2_simple_demo.zig",
        "examples/v2_simd_demo.zig",
    };

    for (example_files) |example_file| {
        const example_name = std.fs.path.stem(example_file);
        const example_exe = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path(example_file),
            .target = exe.root_module.resolved_target,
            .optimize = exe.root_module.optimize.?,
        });
        example_exe.root_module.addImport("zmin_lib", module_registry.lib_mod);
        b.installArtifact(example_exe);
        examples_step.dependOn(&example_exe.step);
    }
}
