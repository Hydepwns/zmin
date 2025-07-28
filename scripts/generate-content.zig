const std = @import("std");

// Content generator for zmin documentation
// This script generates content files from centralized data

const SiteData = struct {
    project: Project,
    examples: Examples,
    bindings: []Binding,
    api: Api,
};

const Project = struct {
    name: []const u8,
    description: []const u8,
    tagline: []const u8,
    performance: Performance,
    features: [][]const u8,
    installation: Installation,
    modes: std.StringHashMap(Mode),
    social: Social,
    links: Links,
};

const Performance = struct {
    throughput: []const u8,
    max_throughput: []const u8,
    memory_limit_eco: []const u8,
};

const Installation = struct {
    source: Source,
    requirements: [][]const u8,
};

const Source = struct {
    commands: [][]const u8,
};

const Mode = struct {
    name: []const u8,
    description: []const u8,
    memory_limit: []const u8,
    use_case: []const u8,
};

const Social = struct {
    github: []const u8,
    twitter: []const u8,
};

const Links = struct {
    docs: []const u8,
    api_reference: []const u8,
    examples: []const u8,
    performance: []const u8,
    getting_started: []const u8,
    installation: []const u8,
    gpu: []const u8,
    troubleshooting: []const u8,
};

const Examples = struct {
    basic: []Example,
    advanced: []Example,
    monitoring: []Example,
};

const Example = struct {
    name: []const u8,
    description: []const u8,
    file: ?[]const u8,
    path: ?[]const u8,
};

const Binding = struct {
    name: []const u8,
    package: ?[]const u8,
    cli_package: ?[]const u8,
    path: []const u8,
};

const Api = struct {
    functions_count: u32,
    types_count: u32,
    json_reference: []const u8,
    yaml_reference: []const u8,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Load site data from YAML
    const site_data = try loadSiteData(allocator);
    defer site_data.deinit();

    // Generate content files
    try generateExamplesReadme(allocator, site_data);
    try generateApiReference(allocator, site_data);
    try generateGettingStarted(allocator, site_data);

    std.debug.print("Content generation complete!\n", .{});
}

fn loadSiteData(allocator: std.mem.Allocator) !SiteData {
    // This would load from data/site.yaml
    // For now, return mock data

    var modes = std.StringHashMap(Mode).init(allocator);
    try modes.put("eco", .{
        .name = "ECO",
        .description = "Energy-efficient mode",
        .memory_limit = "64KB",
        .use_case = "Memory limited environments",
    });
    try modes.put("sport", .{
        .name = "SPORT",
        .description = "Balanced performance mode",
        .memory_limit = "Default",
        .use_case = "General purpose",
    });
    try modes.put("turbo", .{
        .name = "TURBO",
        .description = "Maximum performance mode",
        .memory_limit = "Unlimited",
        .use_case = "Large datasets",
    });

    return SiteData{
        .project = .{
            .name = "zmin",
            .description = "High-performance JSON minifier written in Zig with GPU acceleration",
            .tagline = "Ultra-fast JSON minifier written in Zig",
            .performance = .{
                .throughput = "1.1 GB/s",
                .max_throughput = "3 GB/s",
                .memory_limit_eco = "64KB",
            },
            .features = &[_][]const u8{
                "Multiple modes: Eco, Sport, and Turbo for different use cases",
                "GPU acceleration: CUDA and OpenCL support",
                "Parallel processing: Multi-threaded with NUMA optimization",
                "Streaming: Process large files without loading into memory",
                "Validation: Built-in JSON validation",
                "Plugin system: Extensible architecture",
            },
            .installation = .{
                .source = .{
                    .commands = &[_][]const u8{
                        "git clone https://github.com/hydepwns/zmin",
                        "cd zmin",
                        "zig build install",
                    },
                },
                .requirements = &[_][]const u8{
                    "Zig 0.14.1 or later",
                    "64-bit processor (x86_64 or ARM64)",
                    "Linux, macOS, or Windows",
                    "Minimum 64MB RAM (more for large files)",
                },
            },
            .modes = modes,
            .social = .{
                .github = "https://github.com/hydepwns/zmin",
                .twitter = "https://twitter.com/MF_DROO",
            },
            .links = .{
                .docs = "/docs/",
                .api_reference = "/api-reference-generated.html",
                .examples = "/docs/examples/",
                .performance = "/docs/performance/",
                .getting_started = "/docs/getting-started/",
                .installation = "/docs/installation/",
                .gpu = "/docs/gpu/",
                .troubleshooting = "/docs/troubleshooting/",
            },
        },
        .examples = .{
            .basic = &[_]Example{
                .{ .name = "basic_usage.zig", .description = "Simple minification example", .file = "examples/basic_usage.zig", .path = null },
                .{ .name = "mode_selection.zig", .description = "Using different processing modes", .file = "examples/mode_selection.zig", .path = null },
                .{ .name = "streaming.zig", .description = "Processing large files with streaming", .file = "examples/streaming.zig", .path = null },
            },
            .advanced = &[_]Example{
                .{ .name = "parallel_batch.zig", .description = "Batch processing multiple files", .file = "examples/parallel_batch.zig", .path = null },
            },
            .monitoring = &[_]Example{
                .{ .name = "monitoring", .description = "Performance monitoring examples", .file = null, .path = "examples/monitoring/" },
            },
        },
        .bindings = &[_]Binding{
            .{ .name = "Node.js", .package = "npm install zmin", .cli_package = "npm install @zmin/cli", .path = "bindings/nodejs/" },
            .{ .name = "Python", .package = "pip install zmin", .cli_package = null, .path = "bindings/python/" },
            .{ .name = "Go", .package = "go get github.com/hydepwns/zmin/go", .cli_package = null, .path = "bindings/go/" },
            .{ .name = "NPM CLI", .package = null, .cli_package = "npm install -g @zmin/cli", .path = "bindings/npm/" },
        },
        .api = .{
            .functions_count = 513,
            .types_count = 149,
            .json_reference = "/docs/api-reference-generated.json",
            .yaml_reference = "/docs/api-reference.yaml",
        },
    };
}

fn generateExamplesReadme(allocator: std.mem.Allocator, site_data: SiteData) !void {
    const content =
        \\# {{ .Site.Data.site.project.name }} Examples
        \\
        \\This directory contains examples demonstrating various use cases for {{ .Site.Data.site.project.name }}.
        \\
        \\## Basic Examples
        \\
    ;

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    try output.appendSlice(content);

    for (site_data.examples.basic) |example| {
        try output.writer().print("- [{s}]({s}) - {s}\n", .{
            example.name,
            example.file orelse example.path orelse "",
            example.description,
        });
    }

    try output.appendSlice("\n## Advanced Examples\n\n");

    for (site_data.examples.advanced) |example| {
        try output.writer().print("- [{s}]({s}) - {s}\n", .{
            example.name,
            example.file orelse example.path orelse "",
            example.description,
        });
    }

    try output.appendSlice("\n## Language Bindings\n\n");

    for (site_data.bindings) |binding| {
        try output.writer().print("- **[{s}]({s})** - ", .{ binding.name, binding.path });
        if (binding.package) |pkg| {
            try output.writer().print("`{s}`", .{pkg});
        }
        if (binding.cli_package) |cli_pkg| {
            if (binding.package != null) {
                try output.appendSlice(" or ");
            }
            try output.writer().print("`{s}`", .{cli_pkg});
        }
        try output.appendSlice("\n");
    }

    try output.appendSlice("\n## Building Examples\n\n");
    try output.appendSlice("```bash\n");
    try output.appendSlice("# Build all examples\n");
    try output.appendSlice("zig build examples\n\n");
    try output.appendSlice("# Build specific example\n");
    try output.appendSlice("zig build-exe examples/basic_usage.zig -lc\n\n");
    try output.appendSlice("# Run example\n");
    try output.appendSlice("./basic_usage input.json output.json\n");
    try output.appendSlice("```\n");

    try output.appendSlice("\n## Documentation\n\n");
    try output.writer().print("For complete documentation, visit **[zmin.droo.foo](https://zmin.droo.foo)**\n", .{});

    try std.fs.cwd().writeFile("examples/README.md", output.items);
}

fn generateApiReference(allocator: std.mem.Allocator, site_data: SiteData) !void {
    _ = allocator;
    _ = site_data;
    // Implementation for generating API reference
}

fn generateGettingStarted(allocator: std.mem.Allocator, site_data: SiteData) !void {
    _ = allocator;
    _ = site_data;
    // Implementation for generating getting started guide
}

fn deinitSiteData(self: SiteData) void {
    self.project.modes.deinit();
}
