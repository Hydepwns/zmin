# zmin Plugin API Documentation

This document describes the API for developing plugins for the zmin JSON minification toolkit.

## Overview

zmin supports a plugin system that allows developers to extend the minification capabilities with custom processing logic. Plugins are dynamically loaded shared libraries that implement the zmin Plugin Interface.

### Plugin Types

- **Minifier Plugins**: Custom JSON minification algorithms
- **Validator Plugins**: JSON validation and linting
- **Transformer Plugins**: Data transformation and formatting
- **Analyzer Plugins**: JSON analysis and reporting

## Plugin Interface

### Core Interface

All plugins must implement the base Plugin interface:

```zig
// src/plugins/interface.zig
const std = @import("std");

pub const PluginType = enum {
    minifier,
    validator,
    transformer,
    analyzer,
};

pub const PluginInfo = struct {
    name: []const u8,
    version: []const u8,
    plugin_type: PluginType,
    description: []const u8,
    author: []const u8,
    license: []const u8,
    api_version: []const u8,
    capabilities: []const []const u8,
    dependencies: []const []const u8,
};

pub const Plugin = struct {
    const Self = @This();
    
    // Required: Plugin information
    pub fn getInfo(self: *Self) PluginInfo;
    
    // Required: Plugin initialization
    pub fn init(self: *Self, allocator: std.mem.Allocator) !void;
    
    // Required: Plugin cleanup
    pub fn deinit(self: *Self) void;
    
    // Plugin-specific interface methods (see sections below)
};
```

### Plugin Export

Every plugin must export a creation function:

```zig
// Plugin entry point
pub export fn createPlugin() ?*anyopaque {
    return @ptrCast(&MyPlugin{});
}

// Plugin info function
pub export fn getPluginInfo() PluginInfo {
    return PluginInfo{
        .name = "my-plugin",
        .version = "1.0.0",
        .plugin_type = .minifier,
        .description = "Custom minification plugin",
        .author = "Developer Name",
        .license = "MIT",
        .api_version = "1.0.0",
        .capabilities = &[_][]const u8{"minify", "validate"},
        .dependencies = &[_][]const u8{},
    };
}
```

## Minifier Plugins

### Interface

```zig
pub const MinifierPlugin = struct {
    const Self = @This();
    
    // Required: Minify JSON input
    pub fn minify(self: *Self, allocator: std.mem.Allocator, input: []const u8) ![]const u8;
    
    // Optional: Configuration
    pub fn configure(self: *Self, config: std.json.Value) !void;
    
    // Optional: Get processing statistics
    pub fn getStats(self: *Self) MinifierStats;
};

pub const MinifierStats = struct {
    bytes_processed: usize,
    compression_ratio: f64,
    processing_time_ns: u64,
};
```

### Example Implementation

```zig
// examples/plugins/simple_minifier.zig
const std = @import("std");
const plugin_interface = @import("plugin_interface");

pub const SimpleMinifier = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    stats: plugin_interface.MinifierStats,
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .stats = std.mem.zeroes(plugin_interface.MinifierStats),
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    pub fn minify(self: *Self, allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
        const start_time = std.time.nanoTimestamp();
        
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        var in_string = false;
        var escape_next = false;
        
        for (input) |char| {
            if (escape_next) {
                try result.append(char);
                escape_next = false;
                continue;
            }
            
            switch (char) {
                '\\' => {
                    try result.append(char);
                    if (in_string) {
                        escape_next = true;
                    }
                },
                '"' => {
                    try result.append(char);
                    in_string = !in_string;
                },
                ' ', '\t', '\n', '\r' => {
                    if (in_string) {
                        try result.append(char);
                    }
                    // Skip whitespace outside strings
                },
                else => {
                    try result.append(char);
                },
            }
        }
        
        const output = try result.toOwnedSlice();
        
        // Update statistics
        const end_time = std.time.nanoTimestamp();
        self.stats = plugin_interface.MinifierStats{
            .bytes_processed = input.len,
            .compression_ratio = @as(f64, @floatFromInt(input.len)) / @as(f64, @floatFromInt(output.len)),
            .processing_time_ns = @intCast(end_time - start_time),
        };
        
        return output;
    }
    
    pub fn getStats(self: *Self) plugin_interface.MinifierStats {
        return self.stats;
    }
    
    pub fn getInfo() plugin_interface.PluginInfo {
        return plugin_interface.PluginInfo{
            .name = "simple-minifier",
            .version = "1.0.0",
            .plugin_type = .minifier,
            .description = "Simple whitespace removal minifier",
            .author = "zmin team",
            .license = "MIT",
            .api_version = "1.0.0",
            .capabilities = &[_][]const u8{"minify"},
            .dependencies = &[_][]const u8{},
        };
    }
};

// Plugin exports
var plugin_instance = SimpleMinifier.init(std.heap.page_allocator);

pub export fn createPlugin() ?*anyopaque {
    return @ptrCast(&plugin_instance);
}

pub export fn getPluginInfo() plugin_interface.PluginInfo {
    return SimpleMinifier.getInfo();
}
```

## Validator Plugins

### Interface

```zig
pub const ValidatorPlugin = struct {
    const Self = @This();
    
    // Required: Validate JSON input
    pub fn validate(self: *Self, allocator: std.mem.Allocator, input: []const u8) !ValidationResult;
    
    // Optional: Configuration
    pub fn configure(self: *Self, config: std.json.Value) !void;
};

pub const ValidationResult = struct {
    is_valid: bool,
    errors: []ValidationError,
    warnings: []ValidationWarning,
};

pub const ValidationError = struct {
    line: u32,
    column: u32,
    message: []const u8,
    error_type: ValidationErrorType,
};

pub const ValidationWarning = struct {
    line: u32,
    column: u32,
    message: []const u8,
    warning_type: ValidationWarningType,
};

pub const ValidationErrorType = enum {
    syntax_error,
    invalid_value,
    missing_property,
    type_mismatch,
    constraint_violation,
};

pub const ValidationWarningType = enum {
    deprecated_feature,
    performance_concern,
    style_guideline,
    redundant_data,
};
```

### Example Implementation

```zig
// examples/plugins/strict_validator.zig
const std = @import("std");
const plugin_interface = @import("plugin_interface");

pub const StrictValidator = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    strict_mode: bool,
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .strict_mode = true,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    pub fn validate(self: *Self, allocator: std.mem.Allocator, input: []const u8) !plugin_interface.ValidationResult {
        var errors = std.ArrayList(plugin_interface.ValidationError).init(allocator);
        var warnings = std.ArrayList(plugin_interface.ValidationWarning).init(allocator);
        
        // Basic JSON parsing validation
        var parser = std.json.Parser.init(allocator, false);
        defer parser.deinit();
        
        var tree = parser.parse(input) catch |err| {
            try errors.append(plugin_interface.ValidationError{
                .line = 1,
                .column = 1,
                .message = try std.fmt.allocPrint(allocator, "JSON parsing failed: {}", .{err}),
                .error_type = .syntax_error,
            });
            
            return plugin_interface.ValidationResult{
                .is_valid = false,
                .errors = try errors.toOwnedSlice(),
                .warnings = try warnings.toOwnedSlice(),
            };
        };
        defer tree.deinit();
        
        // Additional strict validations
        try self.validateStrict(allocator, &tree.root, &errors, &warnings);
        
        const error_slice = try errors.toOwnedSlice();
        const warning_slice = try warnings.toOwnedSlice();
        
        return plugin_interface.ValidationResult{
            .is_valid = error_slice.len == 0,
            .errors = error_slice,
            .warnings = warning_slice,
        };
    }
    
    fn validateStrict(
        self: *Self,
        allocator: std.mem.Allocator,
        node: *std.json.Value,
        errors: *std.ArrayList(plugin_interface.ValidationError),
        warnings: *std.ArrayList(plugin_interface.ValidationWarning),
    ) !void {
        switch (node.*) {
            .Object => |obj| {
                // Check for duplicate keys (implementation specific)
                // Check for reserved keywords
                var it = obj.iterator();
                while (it.next()) |entry| {
                    if (std.mem.startsWith(u8, entry.key_ptr.*, "__")) {
                        try warnings.append(plugin_interface.ValidationWarning{
                            .line = 0,
                            .column = 0,
                            .message = try std.fmt.allocPrint(allocator, "Key '{}' uses reserved prefix '__'", .{entry.key_ptr.*}),
                            .warning_type = .style_guideline,
                        });
                    }
                    
                    try self.validateStrict(allocator, entry.value_ptr, errors, warnings);
                }
            },
            .Array => |arr| {
                for (arr.items) |*item| {
                    try self.validateStrict(allocator, item, errors, warnings);
                }
            },
            else => {},
        }
    }
    
    pub fn configure(self: *Self, config: std.json.Value) !void {
        if (config.Object.get("strict_mode")) |strict| {
            if (strict == .Bool) {
                self.strict_mode = strict.Bool;
            }
        }
    }
    
    pub fn getInfo() plugin_interface.PluginInfo {
        return plugin_interface.PluginInfo{
            .name = "strict-validator",
            .version = "1.0.0",
            .plugin_type = .validator,
            .description = "Strict JSON validation with style checking",
            .author = "zmin team",
            .license = "MIT",
            .api_version = "1.0.0",
            .capabilities = &[_][]const u8{"validate", "lint"},
            .dependencies = &[_][]const u8{},
        };
    }
};

// Plugin exports
var plugin_instance = StrictValidator.init(std.heap.page_allocator);

pub export fn createPlugin() ?*anyopaque {
    return @ptrCast(&plugin_instance);
}

pub export fn getPluginInfo() plugin_interface.PluginInfo {
    return StrictValidator.getInfo();
}
```

## Transformer Plugins

### Interface

```zig
pub const TransformerPlugin = struct {
    const Self = @This();
    
    // Required: Transform JSON input
    pub fn transform(self: *Self, allocator: std.mem.Allocator, input: []const u8) ![]const u8;
    
    // Optional: Configuration
    pub fn configure(self: *Self, config: std.json.Value) !void;
    
    // Optional: Get transformation info
    pub fn getTransformInfo(self: *Self) TransformInfo;
};

pub const TransformInfo = struct {
    transform_type: []const u8,
    input_size: usize,
    output_size: usize,
    processing_time_ns: u64,
};
```

### Example Implementation

```zig
// examples/plugins/formatter.zig
const std = @import("std");
const plugin_interface = @import("plugin_interface");

pub const FormatterPlugin = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    indent_size: u32,
    use_tabs: bool,
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .indent_size = 2,
            .use_tabs = false,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    pub fn transform(self: *Self, allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
        // Parse JSON
        var parser = std.json.Parser.init(allocator, false);
        defer parser.deinit();
        
        var tree = try parser.parse(input);
        defer tree.deinit();
        
        // Format with pretty printing
        var formatted = std.ArrayList(u8).init(allocator);
        defer formatted.deinit();
        
        try self.formatValue(&tree.root, formatted.writer(), 0);
        
        return try formatted.toOwnedSlice();
    }
    
    fn formatValue(self: *Self, value: *std.json.Value, writer: anytype, indent_level: u32) !void {
        switch (value.*) {
            .Object => |obj| {
                try writer.writeAll("{\n");
                
                var it = obj.iterator();
                var first = true;
                while (it.next()) |entry| {
                    if (!first) {
                        try writer.writeAll(",\n");
                    }
                    first = false;
                    
                    try self.writeIndent(writer, indent_level + 1);
                    try writer.print("\"{s}\": ", .{entry.key_ptr.*});
                    try self.formatValue(entry.value_ptr, writer, indent_level + 1);
                }
                
                try writer.writeAll("\n");
                try self.writeIndent(writer, indent_level);
                try writer.writeAll("}");
            },
            .Array => |arr| {
                try writer.writeAll("[\n");
                
                for (arr.items, 0..) |*item, i| {
                    if (i > 0) {
                        try writer.writeAll(",\n");
                    }
                    
                    try self.writeIndent(writer, indent_level + 1);
                    try self.formatValue(item, writer, indent_level + 1);
                }
                
                try writer.writeAll("\n");
                try self.writeIndent(writer, indent_level);
                try writer.writeAll("]");
            },
            .String => |str| {
                try writer.print("\"{s}\"", .{str});
            },
            .Integer => |int| {
                try writer.print("{d}", .{int});
            },
            .Float => |float| {
                try writer.print("{d}", .{float});
            },
            .Bool => |boolean| {
                try writer.writeAll(if (boolean) "true" else "false");
            },
            .Null => {
                try writer.writeAll("null");
            },
        }
    }
    
    fn writeIndent(self: *Self, writer: anytype, level: u32) !void {
        var i: u32 = 0;
        while (i < level) : (i += 1) {
            if (self.use_tabs) {
                try writer.writeAll("\t");
            } else {
                var j: u32 = 0;
                while (j < self.indent_size) : (j += 1) {
                    try writer.writeAll(" ");
                }
            }
        }
    }
    
    pub fn configure(self: *Self, config: std.json.Value) !void {
        if (config.Object.get("indent_size")) |indent| {
            if (indent == .Integer) {
                self.indent_size = @intCast(indent.Integer);
            }
        }
        
        if (config.Object.get("use_tabs")) |tabs| {
            if (tabs == .Bool) {
                self.use_tabs = tabs.Bool;
            }
        }
    }
    
    pub fn getInfo() plugin_interface.PluginInfo {
        return plugin_interface.PluginInfo{
            .name = "formatter",
            .version = "1.0.0",
            .plugin_type = .transformer,
            .description = "Pretty-print JSON formatter",
            .author = "zmin team",
            .license = "MIT",
            .api_version = "1.0.0",
            .capabilities = &[_][]const u8{"format", "pretty-print"},
            .dependencies = &[_][]const u8{},
        };
    }
};

// Plugin exports
var plugin_instance = FormatterPlugin.init(std.heap.page_allocator);

pub export fn createPlugin() ?*anyopaque {
    return @ptrCast(&plugin_instance);
}

pub export fn getPluginInfo() plugin_interface.PluginInfo {
    return FormatterPlugin.getInfo();
}
```

## Analyzer Plugins

### Interface

```zig
pub const AnalyzerPlugin = struct {
    const Self = @This();
    
    // Required: Analyze JSON input
    pub fn analyze(self: *Self, allocator: std.mem.Allocator, input: []const u8) !AnalysisResult;
    
    // Optional: Configuration
    pub fn configure(self: *Self, config: std.json.Value) !void;
};

pub const AnalysisResult = struct {
    metrics: AnalysisMetrics,
    issues: []AnalysisIssue,
    recommendations: [][]const u8,
};

pub const AnalysisMetrics = struct {
    total_size: usize,
    object_count: u32,
    array_count: u32,
    string_count: u32,
    number_count: u32,
    boolean_count: u32,
    null_count: u32,
    max_depth: u32,
    avg_key_length: f64,
    avg_string_length: f64,
};

pub const AnalysisIssue = struct {
    severity: IssueSeverity,
    category: IssueCategory,
    message: []const u8,
    location: Location,
};

pub const IssueSeverity = enum {
    info,
    warning,
    error,
    critical,
};

pub const IssueCategory = enum {
    performance,
    structure,
    data_quality,
    security,
    compatibility,
};

pub const Location = struct {
    line: u32,
    column: u32,
    path: []const u8,
};
```

## Plugin Development Guide

### Setting Up Development Environment

```bash
# Create plugin directory
mkdir my-plugin
cd my-plugin

# Create build.zig
cat > build.zig << 'EOF'
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const plugin = b.addSharedLibrary(.{
        .name = "my-plugin",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add plugin interface dependency
    const plugin_interface = b.createModule(.{
        .root_source_file = .{ .path = "../src/plugins/interface.zig" },
    });
    plugin.root_module.addImport("plugin_interface", plugin_interface);

    b.installArtifact(plugin);
}
EOF

# Create source directory
mkdir src
```

### Plugin Manifest

Create a `plugin.json` file describing your plugin:

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "My custom zmin plugin",
  "author": "Your Name",
  "license": "MIT",
  "homepage": "https://github.com/yourname/my-plugin",
  "repository": "https://github.com/yourname/my-plugin.git",
  "api_version": "1.0.0",
  "plugin_type": "minifier",
  "capabilities": ["minify", "validate"],
  "dependencies": [],
  "configuration": {
    "schema": {
      "type": "object",
      "properties": {
        "aggressive_mode": {
          "type": "boolean",
          "default": false
        },
        "preserve_formatting": {
          "type": "boolean", 
          "default": true
        }
      }
    }
  },
  "entry_points": {
    "shared_library": "zig-out/lib/libmy-plugin.so",
    "static_library": "zig-out/lib/libmy-plugin.a"
  },
  "platforms": ["linux", "macos", "windows"],
  "architectures": ["x86_64", "aarch64"],
  "minimum_zmin_version": "1.0.0"
}
```

### Building Plugins

```bash
# Build plugin
zig build

# Install plugin locally
mkdir -p ~/.zmin/plugins
cp zig-out/lib/* ~/.zmin/plugins/
cp plugin.json ~/.zmin/plugins/

# Test plugin
plugin-registry discover
plugin-registry list
plugin-registry test
```

### Testing Plugins

```bash
# Create test script
cat > test-plugin.sh << 'EOF'
#!/bin/bash

echo "Testing plugin..."

# Test data
cat > test.json << 'JSON'
{
  "name": "test",
  "data": [1, 2, 3],
  "nested": {
    "key": "value"
  }
}
JSON

# Test with plugin registry
plugin-registry discover
plugin-registry load
plugin-registry test

echo "Plugin test completed"
EOF

chmod +x test-plugin.sh
./test-plugin.sh
```

## Best Practices

### Error Handling

```zig
pub fn minify(self: *Self, allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    // Validate input
    if (input.len == 0) {
        return error.EmptyInput;
    }
    
    // Check for valid JSON
    var parser = std.json.Parser.init(allocator, false);
    defer parser.deinit();
    
    var tree = parser.parse(input) catch |err| switch (err) {
        error.SyntaxError => return error.InvalidJson,
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ProcessingFailed,
    };
    defer tree.deinit();
    
    // Process safely
    return self.processJson(allocator, &tree.root) catch |err| {
        // Log error details
        std.log.err("Plugin processing failed: {}", .{err});
        return err;
    };
}
```

### Memory Management

```zig
pub fn process(self: *Self, allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    // Use arena allocator for temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();
    
    // Process with temporary allocator
    const temp_result = try self.processInternal(temp_allocator, input);
    
    // Return final result with original allocator
    return try allocator.dupe(u8, temp_result);
}
```

### Configuration

```zig
const Config = struct {
    mode: ProcessingMode = .balanced,
    preserve_whitespace: bool = false,
    max_depth: u32 = 64,
    
    const ProcessingMode = enum {
        fast,
        balanced,
        thorough,
    };
};

pub fn configure(self: *Self, config: std.json.Value) !void {
    if (config.Object.get("mode")) |mode_val| {
        if (mode_val == .String) {
            self.config.mode = std.meta.stringToEnum(Config.ProcessingMode, mode_val.String) orelse .balanced;
        }
    }
    
    if (config.Object.get("preserve_whitespace")) |preserve| {
        if (preserve == .Bool) {
            self.config.preserve_whitespace = preserve.Bool;
        }
    }
    
    if (config.Object.get("max_depth")) |depth| {
        if (depth == .Integer) {
            self.config.max_depth = @intCast(depth.Integer);
        }
    }
}
```

### Performance Optimization

```zig
pub fn minify(self: *Self, allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    // Pre-allocate based on estimated output size
    const estimated_size = @max(input.len / 2, 64);
    var result = try std.ArrayList(u8).initCapacity(allocator, estimated_size);
    defer result.deinit();
    
    // Use buffered writer for better performance
    var buffered_writer = std.io.bufferedWriter(result.writer());
    const writer = buffered_writer.writer();
    
    // Process efficiently
    try self.processStream(writer, input);
    try buffered_writer.flush();
    
    return try result.toOwnedSlice();
}
```

## Plugin Distribution

### Packaging

```bash
#!/bin/bash
# package-plugin.sh

PLUGIN_NAME="my-plugin"
VERSION="1.0.0"

echo "Packaging $PLUGIN_NAME v$VERSION..."

# Build for multiple platforms
TARGETS=("x86_64-linux" "x86_64-macos" "aarch64-macos" "x86_64-windows")

for target in "${TARGETS[@]}"; do
    echo "Building for $target..."
    zig build -Dtarget=$target --release=fast
    
    # Create platform-specific package
    mkdir -p "dist/$PLUGIN_NAME-$VERSION-$target"
    cp zig-out/lib/* "dist/$PLUGIN_NAME-$VERSION-$target/"
    cp plugin.json "dist/$PLUGIN_NAME-$VERSION-$target/"
    cp README.md "dist/$PLUGIN_NAME-$VERSION-$target/"
    
    # Create archive
    tar -czf "dist/$PLUGIN_NAME-$VERSION-$target.tar.gz" -C dist "$PLUGIN_NAME-$VERSION-$target"
done

echo "Packaging completed"
```

### Installation Script

```bash
#!/bin/bash
# install.sh

PLUGIN_NAME="my-plugin"
INSTALL_DIR="$HOME/.zmin/plugins"

echo "Installing $PLUGIN_NAME..."

# Create plugin directory
mkdir -p "$INSTALL_DIR"

# Copy plugin files
cp *.so "$INSTALL_DIR/" 2>/dev/null || cp *.dll "$INSTALL_DIR/" 2>/dev/null || cp *.dylib "$INSTALL_DIR/"
cp plugin.json "$INSTALL_DIR/"

# Refresh plugin registry
if command -v plugin-registry >/dev/null 2>&1; then
    plugin-registry discover
    echo "✅ Plugin installed and registered"
else
    echo "✅ Plugin installed (run 'plugin-registry discover' to register)"
fi
```

## API Reference

### Core Functions

- `createPlugin()`: Plugin factory function
- `getPluginInfo()`: Plugin metadata function
- `init()`: Plugin initialization
- `deinit()`: Plugin cleanup

### Minifier Interface

- `minify(allocator, input)`: Process JSON input
- `configure(config)`: Configure plugin settings
- `getStats()`: Get processing statistics

### Validator Interface

- `validate(allocator, input)`: Validate JSON input
- `configure(config)`: Configure validation rules

### Transformer Interface

- `transform(allocator, input)`: Transform JSON input
- `configure(config)`: Configure transformation options

### Analyzer Interface

- `analyze(allocator, input)`: Analyze JSON structure
- `configure(config)`: Configure analysis parameters

For complete API documentation and examples, see the `examples/plugins/` directory in the zmin repository.