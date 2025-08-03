//! Common Build Helper Functions
//!
//! This module provides reusable build configuration and helper functions
//! to reduce duplication in build.zig files.

const std = @import("std");

/// Common optimization modes with descriptions
pub const OptimizationModes = struct {
    pub const preferred_default: std.builtin.OptimizeMode = .ReleaseFast;
    
    pub fn getDescription(mode: std.builtin.OptimizeMode) []const u8 {
        return switch (mode) {
            .Debug => "Debug mode with safety checks",
            .ReleaseSafe => "Release with safety checks",
            .ReleaseFast => "Release optimized for speed",
            .ReleaseSmall => "Release optimized for size",
        };
    }
};

/// Common build configuration
pub const BuildConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    
    /// Common feature flags
    enable_simd: bool = true,
    enable_parallel: bool = true,
    enable_benchmarks: bool = true,
    enable_tracy: bool = false,
    enable_logging: bool = true,
    
    /// Version info
    version: std.SemanticVersion = .{ .major = 2, .minor = 0, .patch = 0 },
    
    pub fn fromBuild(b: *std.Build) BuildConfig {
        return .{
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{
                .preferred_optimize_mode = OptimizationModes.preferred_default,
            }),
        };
    }
};

/// Create a standard executable with common settings
pub fn createExecutable(
    b: *std.Build,
    name: []const u8,
    root_source: []const u8,
    config: BuildConfig,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(root_source),
        .target = config.target,
        .optimize = config.optimize,
        .version = config.version,
    });
    
    // Apply common settings
    applyCommonSettings(exe, config);
    
    return exe;
}

/// Create a standard library with common settings
pub fn createLibrary(
    b: *std.Build,
    name: []const u8,
    root_source: []const u8,
    config: BuildConfig,
) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = name,
        .root_source_file = b.path(root_source),
        .target = config.target,
        .optimize = config.optimize,
        .version = config.version,
    });
    
    // Apply common settings
    applyCommonSettings(lib, config);
    
    return lib;
}

/// Create a test executable with common settings
pub fn createTest(
    b: *std.Build,
    name: []const u8,
    root_source: []const u8,
    config: BuildConfig,
) *std.Build.Step.Compile {
    const test_exe = b.addTest(.{
        .name = name,
        .root_source_file = b.path(root_source),
        .target = config.target,
        .optimize = config.optimize,
    });
    
    // Apply common settings
    applyCommonSettings(test_exe, config);
    
    return test_exe;
}

/// Apply common build settings
fn applyCommonSettings(compile: *std.Build.Step.Compile, config: BuildConfig) void {
    // Add build options
    const options = compile.step.owner.addOptions();
    options.addOption(bool, "enable_simd", config.enable_simd);
    options.addOption(bool, "enable_parallel", config.enable_parallel);
    options.addOption(bool, "enable_benchmarks", config.enable_benchmarks);
    options.addOption(bool, "enable_tracy", config.enable_tracy);
    options.addOption(bool, "enable_logging", config.enable_logging);
    
    compile.root_module.addOptions("build_options", options);
    
    // Platform-specific optimizations
    if (config.optimize != .Debug) {
        if (compile.rootModuleTarget().cpu.arch.isX86()) {
            // Enable x86 optimizations
            compile.root_module.addAnonymousImport("x86_intrin", .{
                .root_source_file = compile.step.owner.path("src/platform/x86_intrin.zig"),
            });
        } else if (compile.rootModuleTarget().cpu.arch.isAarch64()) {
            // Enable ARM optimizations
            compile.root_module.addAnonymousImport("arm_intrin", .{
                .root_source_file = compile.step.owner.path("src/platform/arm_intrin.zig"),
            });
        }
    }
}

/// Create a benchmark executable
pub fn createBenchmark(
    b: *std.Build,
    name: []const u8,
    root_source: []const u8,
    config: BuildConfig,
) *std.Build.Step.Compile {
    const bench = createExecutable(b, name, root_source, .{
        .target = config.target,
        .optimize = .ReleaseFast, // Always optimize benchmarks
        .enable_benchmarks = true,
        .enable_logging = false, // Disable logging in benchmarks
    });
    
    return bench;
}

/// Common module dependencies
pub const ModuleDependencies = struct {
    /// Core modules that most targets need
    pub fn addCoreModules(compile: *std.Build.Step.Compile, modules: anytype) void {
        // Add common modules
        if (@hasField(@TypeOf(modules), "common")) {
            compile.root_module.addImport("common", modules.common);
        }
        if (@hasField(@TypeOf(modules), "core")) {
            compile.root_module.addImport("core", modules.core);
        }
        if (@hasField(@TypeOf(modules), "utils")) {
            compile.root_module.addImport("utils", modules.utils);
        }
    }
    
    /// Add test-specific modules
    pub fn addTestModules(compile: *std.Build.Step.Compile, modules: anytype) void {
        addCoreModules(compile, modules);
        
        if (@hasField(@TypeOf(modules), "test_helpers")) {
            compile.root_module.addImport("test_helpers", modules.test_helpers);
        }
        if (@hasField(@TypeOf(modules), "test_fixtures")) {
            compile.root_module.addImport("test_fixtures", modules.test_fixtures);
        }
    }
    
    /// Add benchmark-specific modules
    pub fn addBenchmarkModules(compile: *std.Build.Step.Compile, modules: anytype) void {
        addCoreModules(compile, modules);
        
        if (@hasField(@TypeOf(modules), "benchmark_utils")) {
            compile.root_module.addImport("benchmark_utils", modules.benchmark_utils);
        }
    }
};

/// Create a module from source file
pub fn createModule(b: *std.Build, name: []const u8, path: []const u8) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(path),
    });
}

/// Batch create modules from a list
pub fn createModules(b: *std.Build, comptime module_list: anytype) type {
    const ModuleStruct = @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = blk: {
                var fields: [module_list.len]std.builtin.Type.StructField = undefined;
                for (module_list, 0..) |module_info, i| {
                    fields[i] = .{
                        .name = module_info.name,
                        .type = *std.Build.Module,
                        .default_value = null,
                        .is_comptime = false,
                        .alignment = @alignOf(*std.Build.Module),
                    };
                }
                break :blk &fields;
            },
            .decls = &.{},
            .is_tuple = false,
        },
    });
    
    var modules: ModuleStruct = undefined;
    
    inline for (module_list) |module_info| {
        @field(modules, module_info.name) = createModule(b, module_info.name, module_info.path);
    }
    
    return modules;
}

/// Common build steps
pub const BuildSteps = struct {
    /// Add a format step
    pub fn addFormatStep(b: *std.Build, name: []const u8, paths: []const []const u8) *std.Build.Step {
        const fmt_step = b.step(name, "Format source code");
        
        const fmt = b.addFmt(.{
            .paths = paths,
            .check = false,
        });
        
        fmt_step.dependOn(&fmt.step);
        return fmt_step;
    }
    
    /// Add a format check step
    pub fn addFormatCheckStep(b: *std.Build, name: []const u8, paths: []const []const u8) *std.Build.Step {
        const fmt_check_step = b.step(name, "Check source code formatting");
        
        const fmt_check = b.addFmt(.{
            .paths = paths,
            .check = true,
        });
        
        fmt_check_step.dependOn(&fmt_check.step);
        return fmt_check_step;
    }
    
    /// Add a clean step
    pub fn addCleanStep(b: *std.Build) *std.Build.Step {
        const clean_step = b.step("clean", "Clean build artifacts");
        
        if (builtin.os.tag == .windows) {
            const clean_cmd = b.addSystemCommand(&.{ "cmd", "/c", "rmdir", "/s", "/q", "zig-out", "zig-cache" });
            clean_step.dependOn(&clean_cmd.step);
        } else {
            const clean_cmd = b.addSystemCommand(&.{ "rm", "-rf", "zig-out", "zig-cache", ".zig-cache" });
            clean_step.dependOn(&clean_cmd.step);
        }
        
        return clean_step;
    }
    
    /// Add a documentation generation step
    pub fn addDocsStep(b: *std.Build, main_module: *std.Build.Module) *std.Build.Step {
        const docs_step = b.step("docs", "Generate documentation");
        
        const docs = b.addStaticLibrary(.{
            .name = "docs",
            .root_source_file = main_module.root_source_file.?,
            .target = b.standardTargetOptions(.{}),
            .optimize = .Debug,
        });
        
        docs.root_module = main_module.*;
        const install_docs = b.addInstallDirectory(.{
            .source_dir = docs.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });
        
        docs_step.dependOn(&install_docs.step);
        return docs_step;
    }
};

/// Test runner configuration
pub const TestRunner = struct {
    /// Create a test suite with multiple test files
    pub fn createTestSuite(
        b: *std.Build,
        name: []const u8,
        test_files: []const []const u8,
        config: BuildConfig,
        modules: anytype,
    ) *std.Build.Step {
        const test_step = b.step(name, "Run test suite");
        
        for (test_files) |test_file| {
            const test_name = std.fs.path.stem(test_file);
            const test_exe = createTest(b, test_name, test_file, config);
            
            ModuleDependencies.addTestModules(test_exe, modules);
            
            const run_test = b.addRunArtifact(test_exe);
            test_step.dependOn(&run_test.step);
        }
        
        return test_step;
    }
    
    /// Add test filters
    pub fn addTestFilter(run_step: *std.Build.Step.Run, filter: []const u8) void {
        run_step.addArg("--test-filter");
        run_step.addArg(filter);
    }
};

/// Example builder configuration
pub const ExampleBuilder = struct {
    /// Build all examples in a directory
    pub fn buildExamples(
        b: *std.Build,
        examples_dir: []const u8,
        config: BuildConfig,
        lib_module: *std.Build.Module,
    ) !*std.Build.Step {
        const examples_step = b.step("examples", "Build all examples");
        
        var dir = try std.fs.cwd().openDir(examples_dir, .{ .iterate = true });
        defer dir.close();
        
        var walker = try dir.walk(b.allocator);
        defer walker.deinit();
        
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.basename, ".zig")) continue;
            
            const example_path = try std.fs.path.join(b.allocator, &.{ examples_dir, entry.path });
            const example_name = std.fs.path.stem(entry.basename);
            
            const example_exe = createExecutable(b, example_name, example_path, config);
            example_exe.root_module.addImport("zmin", lib_module);
            
            b.installArtifact(example_exe);
            examples_step.dependOn(&example_exe.step);
        }
        
        return examples_step;
    }
};

/// Installation helpers
pub const Installer = struct {
    /// Install with custom prefix
    pub fn installWithPrefix(
        b: *std.Build,
        artifact: *std.Build.Step.Compile,
        prefix: []const u8,
    ) void {
        const install = b.addInstallArtifact(artifact, .{
            .dest_dir = .{ .override = .{ .custom = prefix } },
        });
        b.getInstallStep().dependOn(&install.step);
    }
    
    /// Install headers
    pub fn installHeaders(
        b: *std.Build,
        headers_dir: []const u8,
        dest_dir: []const u8,
    ) !void {
        const install_headers = b.addInstallDirectory(.{
            .source_dir = b.path(headers_dir),
            .install_dir = .header,
            .install_subdir = dest_dir,
        });
        
        b.getInstallStep().dependOn(&install_headers.step);
    }
};