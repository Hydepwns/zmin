const std = @import("std");
const types = @import("types.zig");

pub fn createTools(b: *std.Build, config: types.Config, modules: types.ModuleRegistry) void {
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

    // Phase 4: Developer tools
    const zmin_format_exe = b.addExecutable(.{
        .name = "zmin-format",
        .root_source_file = b.path("tools/zmin-format-simple.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    b.installArtifact(zmin_format_exe);

    const zmin_validate_exe = b.addExecutable(.{
        .name = "zmin-validate",
        .root_source_file = b.path("tools/zmin-validate-simple.zig"),
        .target = config.target,
        .optimize = config.optimize,
    });
    // No imports needed for simple version
    b.installArtifact(zmin_validate_exe);

    // Development tools
    const dev_tools = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "config-manager", .path = "tools/config_manager.zig" },
        .{ .name = "hot-reloading", .path = "tools/hot_reloading.zig" },
        .{ .name = "dev-server", .path = "tools/dev_server.zig" },
        .{ .name = "profiler", .path = "tools/profiler.zig" },
        .{ .name = "debugger", .path = "tools/debugger.zig" },
        .{ .name = "plugin-registry", .path = "tools/plugin_registry.zig" },
    };

    for (dev_tools) |tool| {
        const tool_exe = b.addExecutable(.{
            .name = tool.name,
            .root_source_file = b.path(tool.path),
            .target = config.target,
            .optimize = config.optimize,
        });
        tool_exe.root_module.addImport("zmin_lib", modules.lib_mod);
        
        // Add plugin_loader import for plugin_registry
        if (std.mem.eql(u8, tool.name, "plugin-registry")) {
            // Plugin loader needs to be created as a module first
            const plugin_loader_mod = b.createModule(.{
                .root_source_file = b.path("src/plugins/loader.zig"),
            });
            plugin_loader_mod.addImport("plugin_interface", b.createModule(.{
                .root_source_file = b.path("src/plugins/interface.zig"),
            }));
            plugin_loader_mod.addImport("zmin_lib", modules.lib_mod);
            tool_exe.root_module.addImport("plugin_loader", plugin_loader_mod);
        }
        
        b.installArtifact(tool_exe);
    }

    // Tool steps
    const run_performance_monitor = b.addRunArtifact(performance_monitor_exe);
    const performance_monitor_step = b.step("tools:performance-monitor", "Parse benchmark output and generate performance data");
    performance_monitor_step.dependOn(&run_performance_monitor.step);

    const run_badge_generator = b.addRunArtifact(badge_generator_exe);
    const badge_generator_step = b.step("tools:badges", "Generate performance badges");
    badge_generator_step.dependOn(&run_badge_generator.step);

    const run_format = b.addRunArtifact(zmin_format_exe);
    const format_step = b.step("tools:format", "Format minified JSON");
    format_step.dependOn(&run_format.step);

    const run_validate = b.addRunArtifact(zmin_validate_exe);
    const validate_step = b.step("tools:validate", "Validate JSON with detailed errors");
    validate_step.dependOn(&run_validate.step);
}
