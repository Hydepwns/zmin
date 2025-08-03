const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the executable
    const exe = b.addExecutable(.{
        .name = "zmin",
        .root_source_file = b.path("src/main_simple.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Install the executable
    b.installArtifact(exe);

    // Create a run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the JSON minifier");
    run_step.dependOn(&run_cmd.step);

    // Create test step for comprehensive tests
    const comprehensive_test = b.addTest(.{
        .root_source_file = b.path("comprehensive_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_comprehensive_test = b.addRunArtifact(comprehensive_test);

    const test_step = b.step("test", "Run comprehensive tests");
    test_step.dependOn(&run_comprehensive_test.step);
}
