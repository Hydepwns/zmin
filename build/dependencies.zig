const types = @import("types.zig");

pub fn setupModuleDependencies(modules: types.ModuleRegistry) void {
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
