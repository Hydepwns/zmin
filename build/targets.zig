const std = @import("std");
const types = @import("types.zig");

pub fn createLibrary(b: *std.Build, modules: types.ModuleRegistry) *std.Build.Step.Compile {
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zmin",
        .root_module = modules.lib_mod,
    });

    b.installArtifact(lib);
    return lib;
}

pub fn createExecutable(b: *std.Build, modules: types.ModuleRegistry) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "zmin",
        .root_module = modules.exe_mod,
    });

    exe.root_module.strip = false;
    b.installArtifact(exe);

    // Create CLI modules for enhanced executable
    const cli_interactive_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/interactive.zig"),
        .target = exe.root_module.resolved_target,
        .optimize = exe.root_module.optimize.?,
    });
    cli_interactive_mod.addImport("zmin_lib", modules.lib_mod);

    const cli_args_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/args_parser.zig"),
        .target = exe.root_module.resolved_target,
        .optimize = exe.root_module.optimize.?,
    });
    cli_args_mod.addImport("zmin_lib", modules.lib_mod);

    // Enhanced CLI executable
    const cli_exe = b.addExecutable(.{
        .name = "zmin-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main_cli.zig"),
            .target = exe.root_module.resolved_target,
            .optimize = exe.root_module.optimize.?,
        }),
    });
    cli_exe.root_module.addImport("zmin_lib", modules.lib_mod);
    cli_exe.root_module.addImport("cli/interactive.zig", cli_interactive_mod);
    cli_exe.root_module.addImport("cli/args_parser.zig", cli_args_mod);
    cli_exe.root_module.addImport("common", modules.common_mod);
    cli_exe.root_module.strip = false;
    b.installArtifact(cli_exe);

    return exe;
}
