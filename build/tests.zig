const std = @import("std");
const types = @import("types.zig");

pub fn createTestSuite(b: *std.Build, config: types.Config, modules: types.ModuleRegistry) void {
    // Phase 3: Create test framework module
    const test_framework_mod = b.createModule(.{
        .root_source_file = b.path("tests/helpers/test_framework.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    test_framework_mod.addImport("zmin_lib", modules.lib_mod);

    // Create test helper modules
    const test_helpers_mod = b.createModule(.{
        .root_source_file = b.path("tests/helpers/test_helpers.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    test_helpers_mod.addImport("zmin_lib", modules.lib_mod);
    test_helpers_mod.addImport("src", modules.lib_mod);

    const assertion_helpers_mod = b.createModule(.{
        .root_source_file = b.path("tests/helpers/assertion_helpers.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });

    // Create mode test framework module
    const mode_test_framework_mod = b.createModule(.{
        .root_source_file = b.path("tests/modes/mode_test_framework.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    mode_test_framework_mod.addImport("modes", modules.modes_mod);
    mode_test_framework_mod.addImport("minifier_interface", modules.minifier_interface_mod);

    // Create benchmarks module for performance tests
    const performance_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/benchmarks/performance_tests.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    performance_tests_mod.addImport("zmin_lib", modules.lib_mod);
    performance_tests_mod.addImport("mode_test_framework", mode_test_framework_mod);

    // Create basic test modules
    const basic_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/minifier/basic.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    basic_test_mod.addImport("src", modules.lib_mod);
    basic_test_mod.addImport("test_helpers", test_helpers_mod);
    basic_test_mod.addImport("assertion_helpers", assertion_helpers_mod);

    const extended_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/minifier/extended.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    extended_test_mod.addImport("src", modules.lib_mod);
    extended_test_mod.addImport("test_helpers", test_helpers_mod);
    extended_test_mod.addImport("assertion_helpers", assertion_helpers_mod);

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
    mode_tests.root_module.addImport("performance_tests", performance_tests_mod);
    mode_tests.root_module.addImport("mode_test_framework", mode_test_framework_mod);

    // Create test steps
    const lib_unit_tests = b.addTest(.{ .root_module = modules.lib_mod });
    const exe_unit_tests = b.addTest(.{ .root_module = modules.exe_mod });
    const basic_tests = b.addTest(.{ .root_module = basic_test_mod });
    const extended_tests = b.addTest(.{ .root_module = extended_test_mod });
    const parallel_tests = b.addTest(.{ .root_module = parallel_test_mod });
    const parallel_config_tests = b.addTest(.{ .root_module = parallel_config_test_mod });
    const minimal_tests = b.addTest(.{ .root_module = minimal_test_mod });
    const api_consistency_tests = b.addTest(.{ .root_module = api_consistency_test_mod });

    // Phase 3: New test suites
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration/real_world_datasets.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    integration_tests.root_module.addImport("zmin_lib", modules.lib_mod);
    integration_tests.root_module.addImport("test_framework", test_framework_mod);

    const property_tests = b.addTest(.{
        .root_source_file = b.path("tests/property_based_tests.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    property_tests.root_module.addImport("zmin_lib", modules.lib_mod);
    property_tests.root_module.addImport("test_framework", test_framework_mod);

    const fuzz_tests = b.addTest(.{
        .root_source_file = b.path("tests/fuzz/json_fuzzer.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    fuzz_tests.root_module.addImport("zmin_lib", modules.lib_mod);

    const regression_tests = b.addTest(.{
        .root_source_file = b.path("tests/regression/regression_tests.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    regression_tests.root_module.addImport("zmin_lib", modules.lib_mod);
    regression_tests.root_module.addImport("test_framework", test_framework_mod);

    // Dev tools unit tests
    const simple_dev_tools_tests = b.addTest(.{
        .root_source_file = b.path("tests/unit/simple_dev_tools_test.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    
    const dev_tools_unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/unit/dev_tools_tests.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    dev_tools_unit_tests.root_module.addImport("zmin_lib", modules.lib_mod);
    
    const dev_server_unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/unit/dev_server_tests.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    dev_server_unit_tests.root_module.addImport("zmin_lib", modules.lib_mod);
    
    const debugger_unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/unit/debugger_tests.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    debugger_unit_tests.root_module.addImport("zmin_lib", modules.lib_mod);
    
    const plugin_registry_unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/unit/plugin_registry_tests.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    plugin_registry_unit_tests.root_module.addImport("zmin_lib", modules.lib_mod);

    const dev_tools_test_suite = b.addTest(.{
        .root_source_file = b.path("tests/unit/dev_tools_test_suite.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    dev_tools_test_suite.root_module.addImport("zmin_lib", modules.lib_mod);
    dev_tools_test_suite.root_module.addImport("test_framework", test_framework_mod);

    // Simple integration tests that work with current module system

    const simple_integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration/simple_dev_tools_integration.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    simple_integration_tests.root_module.addImport("zmin_lib", modules.lib_mod);

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

    // Phase 3: New test run steps
    const run_integration_tests = b.addRunArtifact(integration_tests);
    const run_property_tests = b.addRunArtifact(property_tests);
    const run_fuzz_tests = b.addRunArtifact(fuzz_tests);
    const run_regression_tests = b.addRunArtifact(regression_tests);

    // Dev tools test run steps
    const run_simple_dev_tools_tests = b.addRunArtifact(simple_dev_tools_tests);
    const run_simple_integration_tests = b.addRunArtifact(simple_integration_tests);
    // Future: Enable when import issues are resolved
    // const run_dev_tools_unit_tests = b.addRunArtifact(dev_tools_unit_tests);
    // const run_dev_server_unit_tests = b.addRunArtifact(dev_server_unit_tests);
    // const run_debugger_unit_tests = b.addRunArtifact(debugger_unit_tests);
    // const run_plugin_registry_unit_tests = b.addRunArtifact(plugin_registry_unit_tests);
    // const run_dev_tools_test_suite = b.addRunArtifact(dev_tools_test_suite);

    // Create test step groups
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_basic_tests.step);
    test_step.dependOn(&run_extended_tests.step);
    test_step.dependOn(&run_parallel_tests.step);
    test_step.dependOn(&run_parallel_config_tests.step);
    test_step.dependOn(&run_minimal_tests.step);
    test_step.dependOn(&run_api_consistency_tests.step);
    test_step.dependOn(&run_mode_tests.step);
    test_step.dependOn(&run_integration_tests.step);
    test_step.dependOn(&run_property_tests.step);
    test_step.dependOn(&run_regression_tests.step);
    test_step.dependOn(&run_simple_dev_tools_tests.step);
    test_step.dependOn(&run_simple_integration_tests.step);

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

    // Add fuzz tests to a separate step
    const test_fuzz_step = b.step("test:fuzz", "Run fuzz tests");
    test_fuzz_step.dependOn(&run_fuzz_tests.step);

    // Dev tools tests
    const test_dev_tools_step = b.step("test:dev-tools", "Run dev tools unit tests");
    test_dev_tools_step.dependOn(&run_simple_dev_tools_tests.step);
    
    // Integration tests
    const test_integration_step = b.step("test:integration", "Run integration tests");
    test_integration_step.dependOn(&run_integration_tests.step);
    test_integration_step.dependOn(&run_simple_integration_tests.step);
    
    // Future: Add more comprehensive tests when import issues are resolved
    // test_dev_tools_step.dependOn(&run_dev_tools_unit_tests.step);
    // test_dev_tools_step.dependOn(&run_dev_server_unit_tests.step);
    // test_dev_tools_step.dependOn(&run_debugger_unit_tests.step);
    // test_dev_tools_step.dependOn(&run_plugin_registry_unit_tests.step);
    // test_dev_tools_step.dependOn(&run_dev_tools_test_suite.step);

    // V2 Streaming Engine Tests
    const v2_tests = b.addTest(.{
        .root_source_file = b.path("tests/v2/all_tests.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    v2_tests.root_module.addImport("src", modules.lib_mod);

    const run_v2_tests = b.addRunArtifact(v2_tests);

    // Add v2 tests to main test step
    test_step.dependOn(&run_v2_tests.step);

    // Create v2-specific test step
    const test_v2_step = b.step("test:v2", "Run v2 streaming engine tests");
    test_v2_step.dependOn(&run_v2_tests.step);
}
