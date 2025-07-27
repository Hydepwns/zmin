const std = @import("std");
const types = @import("types.zig");

pub fn createBenchmarks(b: *std.Build, config: types.Config, modules: types.ModuleRegistry) void {
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
