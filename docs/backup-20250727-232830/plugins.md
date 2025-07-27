# Plugin Development Guide

zmin's plugin system allows you to extend the minifier with custom transformation logic, validators, and optimizers.

## Overview

zmin supports three types of plugins:
- **Minifiers**: Custom minification algorithms
- **Validators**: JSON validation and format checking
- **Optimizers**: Post-processing optimizations

## Plugin Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Input JSON    │───▶│  Plugin Chain   │───▶│  Output JSON    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  Core zmin      │
                    │  (fallback)     │
                    └─────────────────┘
```

## Quick Start

### 1. Create a Basic Minifier Plugin

```zig
// plugins/minifiers/my_minifier.zig
const std = @import("std");
const zmin = @import("../../src/root.zig");

export fn init() callconv(.C) c_int {
    std.log.info("My minifier plugin loaded", .{});
    return 0;
}

export fn minify(
    input: [*c]const u8,
    input_len: usize,
    output: [*c]u8,
    output_len: *usize,
    max_output_len: usize
) callconv(.C) c_int {
    // Custom minification logic here
    const allocator = std.heap.c_allocator;
    
    const input_slice = input[0..input_len];
    
    // Example: Remove all whitespace more aggressively
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    var in_string = false;
    var escape_next = false;
    
    for (input_slice) |char| {
        if (escape_next) {
            result.append(char) catch return -1;
            escape_next = false;
            continue;
        }
        
        switch (char) {
            '"' => {
                in_string = !in_string;
                result.append(char) catch return -1;
            },
            '\\' if in_string => {
                escape_next = true;
                result.append(char) catch return -1;
            },
            ' ', '\t', '\n', '\r' => {
                if (in_string) {
                    result.append(char) catch return -1;
                }
                // Skip whitespace outside strings
            },
            else => {
                result.append(char) catch return -1;
            },
        }
    }
    
    const result_slice = result.toOwnedSlice() catch return -1;
    defer allocator.free(result_slice);
    
    if (result_slice.len > max_output_len) {
        return -2; // Buffer too small
    }
    
    @memcpy(output[0..result_slice.len], result_slice);
    output_len.* = result_slice.len;
    
    return 0; // Success
}

export fn deinit() callconv(.C) void {
    std.log.info("My minifier plugin unloaded", .{});
}

export fn get_info() callconv(.C) [*c]const u8 {
    return "My Custom Minifier v1.0";
}
```

### 2. Build the Plugin

```bash
# Build as shared library
zig build-lib -dynamic plugins/minifiers/my_minifier.zig -femit-bin=zig-out/plugins/minifiers/libmy_minifier.so

# Or use the build system
zig build plugins
```

### 3. Load and Use the Plugin

```bash
# Load plugin at runtime
zmin --plugin ./zig-out/plugins/minifiers/libmy_minifier.so input.json output.json

# Or configure in zmin config
cat > ~/.zmin/config.json << EOF
{
  "plugins": {
    "minifiers": [
      "./zig-out/plugins/minifiers/libmy_minifier.so"
    ]
  }
}
EOF
```

## Plugin API Reference

### Core Interface

All plugins must implement these C-compatible functions:

```zig
// Plugin initialization
export fn init() callconv(.C) c_int;

// Plugin cleanup  
export fn deinit() callconv(.C) void;

// Plugin information
export fn get_info() callconv(.C) [*c]const u8;
```

### Minifier Plugins

```zig
// Main minification function
export fn minify(
    input: [*c]const u8,        // Input JSON string
    input_len: usize,           // Input length
    output: [*c]u8,             // Output buffer
    output_len: *usize,         // Output length (in/out)
    max_output_len: usize       // Maximum output buffer size
) callconv(.C) c_int;

// Estimate output size (optional)
export fn estimate_size(input_len: usize) callconv(.C) usize;

// Check if plugin can handle input (optional)
export fn can_handle(
    input: [*c]const u8,
    input_len: usize
) callconv(.C) c_int;
```

**Return Codes**:
- `0`: Success
- `-1`: General error
- `-2`: Buffer too small
- `-3`: Invalid input
- `-4`: Not supported

### Validator Plugins

```zig
// Validate JSON
export fn validate(
    input: [*c]const u8,
    input_len: usize,
    error_msg: [*c]u8,
    error_msg_len: usize
) callconv(.C) c_int;

// Get validation details
export fn get_validation_info(
    input: [*c]const u8,
    input_len: usize,
    info: [*c]ValidationInfo
) callconv(.C) c_int;

const ValidationInfo = extern struct {
    is_valid: c_int,
    error_line: c_int,
    error_column: c_int,
    error_offset: usize,
    depth: c_int,
    object_count: usize,
    array_count: usize,
};
```

### Optimizer Plugins

```zig
// Post-process minified JSON
export fn optimize(
    input: [*c]const u8,
    input_len: usize,
    output: [*c]u8,
    output_len: *usize,
    max_output_len: usize,
    options: [*c]const OptimizeOptions
) callconv(.C) c_int;

const OptimizeOptions = extern struct {
    sort_keys: c_int,
    remove_duplicates: c_int,
    normalize_numbers: c_int,
    custom_flags: u32,
};
```

## Advanced Plugin Examples

### 1. Schema-Aware Minifier

```zig
// plugins/minifiers/schema_minifier.zig
const std = @import("std");
const json = std.json;

const SchemaRule = struct {
    path: []const u8,
    action: enum { remove, abbreviate, normalize },
    replacement: ?[]const u8 = null,
};

const rules = [_]SchemaRule{
    .{ .path = "metadata.timestamp", .action = .remove },
    .{ .path = "user.preferences", .action = .abbreviate, .replacement = "prefs" },
    .{ .path = "coordinates.latitude", .action = .normalize },
};

export fn minify(
    input: [*c]const u8,
    input_len: usize,
    output: [*c]u8,
    output_len: *usize,
    max_output_len: usize
) callconv(.C) c_int {
    const allocator = std.heap.c_allocator;
    
    // Parse JSON
    const input_slice = input[0..input_len];
    var parsed = json.parseFromSlice(json.Value, allocator, input_slice, .{}) catch return -3;
    defer parsed.deinit();
    
    // Apply schema rules
    applySchemaRules(&parsed.value, "") catch return -1;
    
    // Serialize back to JSON
    var output_list = std.ArrayList(u8).init(allocator);
    defer output_list.deinit();
    
    json.stringify(parsed.value, .{}, output_list.writer()) catch return -1;
    
    const result = output_list.toOwnedSlice() catch return -1;
    defer allocator.free(result);
    
    if (result.len > max_output_len) return -2;
    
    @memcpy(output[0..result.len], result);
    output_len.* = result.len;
    
    return 0;
}

fn applySchemaRules(value: *json.Value, path: []const u8) !void {
    // Implementation of schema rule application
    // This would traverse the JSON and apply transformations
    // based on the defined rules
}
```

### 2. Performance Monitoring Plugin

```zig
// plugins/validators/perf_validator.zig
const std = @import("std");

var start_time: i64 = 0;
var processed_bytes: usize = 0;

export fn init() callconv(.C) c_int {
    start_time = std.time.milliTimestamp();
    processed_bytes = 0;
    return 0;
}

export fn validate(
    input: [*c]const u8,
    input_len: usize,
    error_msg: [*c]u8,
    error_msg_len: usize
) callconv(.C) c_int {
    processed_bytes += input_len;
    
    // Basic JSON validation
    const allocator = std.heap.c_allocator;
    const input_slice = input[0..input_len];
    
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, input_slice, .{}) catch {
        const msg = "Invalid JSON format";
        const copy_len = @min(msg.len, error_msg_len - 1);
        @memcpy(error_msg[0..copy_len], msg[0..copy_len]);
        error_msg[copy_len] = 0;
        return -3;
    };
    parsed.deinit();
    
    // Log performance metrics
    const current_time = std.time.milliTimestamp();
    const elapsed = current_time - start_time;
    if (elapsed > 0) {
        const throughput = processed_bytes * 1000 / @as(usize, @intCast(elapsed));
        std.log.info("Validation throughput: {} bytes/sec", .{throughput});
    }
    
    return 0;
}
```

### 3. Custom Format Optimizer

```zig
// plugins/optimizers/custom_optimizer.zig
const std = @import("std");

export fn optimize(
    input: [*c]const u8,
    input_len: usize,
    output: [*c]u8,
    output_len: *usize,
    max_output_len: usize,
    options: [*c]const OptimizeOptions
) callconv(.C) c_int {
    const allocator = std.heap.c_allocator;
    const input_slice = input[0..input_len];
    
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    // Custom optimizations based on options
    if (options.sort_keys != 0) {
        // Sort object keys alphabetically
        // Implementation would parse JSON and sort keys
    }
    
    if (options.normalize_numbers != 0) {
        // Normalize number formats (remove unnecessary decimals)
        var i: usize = 0;
        while (i < input_slice.len) {
            const char = input_slice[i];
            if (std.ascii.isDigit(char)) {
                // Number normalization logic
                const num_start = i;
                while (i < input_slice.len and (std.ascii.isDigit(input_slice[i]) or input_slice[i] == '.')) {
                    i += 1;
                }
                // Process number and add to result
                const num_str = input_slice[num_start..i];
                const normalized = normalizeNumber(allocator, num_str) catch return -1;
                defer allocator.free(normalized);
                result.appendSlice(normalized) catch return -1;
            } else {
                result.append(char) catch return -1;
                i += 1;
            }
        }
    } else {
        result.appendSlice(input_slice) catch return -1;
    }
    
    const final_result = result.toOwnedSlice() catch return -1;
    defer allocator.free(final_result);
    
    if (final_result.len > max_output_len) return -2;
    
    @memcpy(output[0..final_result.len], final_result);
    output_len.* = final_result.len;
    
    return 0;
}

fn normalizeNumber(allocator: std.mem.Allocator, num_str: []const u8) ![]u8 {
    // Remove trailing zeros and unnecessary decimal points
    // e.g., "1.000" -> "1", "1.500" -> "1.5"
    
    if (std.mem.indexOf(u8, num_str, ".")) |dot_pos| {
        var end = num_str.len;
        while (end > dot_pos + 1 and num_str[end - 1] == '0') {
            end -= 1;
        }
        if (end == dot_pos + 1) {
            end = dot_pos; // Remove decimal point if no fractional part
        }
        return try allocator.dupe(u8, num_str[0..end]);
    }
    
    return try allocator.dupe(u8, num_str);
}
```

## Plugin Configuration

### Configuration File

```json
{
  "plugins": {
    "minifiers": [
      {
        "path": "./plugins/minifiers/libschema_minifier.so",
        "priority": 10,
        "config": {
          "schema_file": "./schemas/api.json",
          "aggressive_mode": true
        }
      }
    ],
    "validators": [
      {
        "path": "./plugins/validators/libperf_validator.so",
        "priority": 5,
        "enabled": true
      }
    ],
    "optimizers": [
      {
        "path": "./plugins/optimizers/libcustom_optimizer.so",
        "priority": 1,
        "config": {
          "sort_keys": true,
          "normalize_numbers": true,
          "remove_duplicates": false
        }
      }
    ]
  },
  "plugin_search_paths": [
    "./plugins/",
    "/usr/local/lib/zmin/plugins/",
    "~/.zmin/plugins/"
  ]
}
```

### Environment Variables

```bash
# Plugin search paths
export ZMIN_PLUGIN_PATH="/custom/plugins:/usr/lib/zmin/plugins"

# Enable plugin debugging
export ZMIN_PLUGIN_DEBUG=1

# Plugin configuration file
export ZMIN_CONFIG="~/.zmin/config.json"
```

## Plugin Utilities

### Helper Functions

zmin provides utility functions for plugin development:

```zig
// Available in plugin context
extern fn zmin_log(level: c_int, message: [*c]const u8) void;
extern fn zmin_get_allocator() *std.mem.Allocator;
extern fn zmin_get_version() [*c]const u8;
extern fn zmin_validate_json(input: [*c]const u8, len: usize) c_int;
```

### Plugin Template

```bash
# Generate plugin template
zmin generate-plugin --type minifier --name my_plugin
# Creates: plugins/minifiers/my_plugin.zig with boilerplate
```

## Testing Plugins

### Unit Testing

```zig
// test/plugin_test.zig
const std = @import("std");
const testing = std.testing;

test "custom minifier basic functionality" {
    const allocator = testing.allocator;
    
    // Load plugin
    const plugin = @import("../plugins/minifiers/my_minifier.zig");
    
    // Test input
    const input = "{ \"hello\" : \"world\" }";
    var output: [1024]u8 = undefined;
    var output_len: usize = 0;
    
    // Call plugin function
    const result = plugin.minify(
        input.ptr,
        input.len,
        &output,
        &output_len,
        output.len
    );
    
    try testing.expect(result == 0);
    try testing.expect(output_len > 0);
    
    const output_str = output[0..output_len];
    try testing.expectEqualStrings("{\"hello\":\"world\"}", output_str);
}
```

### Integration Testing

```bash
# Test plugin with zmin
echo '{"test": true}' | zmin --plugin ./my_plugin.so --test-mode

# Benchmark plugin performance
zmin --plugin ./my_plugin.so --benchmark large-file.json
```

## Plugin Distribution

### Package Structure

```
my-zmin-plugin/
├── README.md
├── LICENSE
├── Makefile
├── build.zig
├── src/
│   └── plugin.zig
├── test/
│   └── test.zig
├── examples/
│   └── usage.md
└── docs/
    └── api.md
```

### Build Script

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const plugin = b.addSharedLibrary(.{
        .name = "my_plugin",
        .root_source_file = .{ .path = "src/plugin.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    plugin.linkLibC();
    b.installArtifact(plugin);
    
    // Tests
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "test/test.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
```

## Best Practices

### Performance

1. **Minimize allocations** in hot paths
2. **Use stack allocation** for small buffers
3. **Implement streaming** for large inputs
4. **Cache expensive computations**
5. **Profile regularly** during development

### Error Handling

```zig
// Always handle errors gracefully
export fn minify(...) callconv(.C) c_int {
    const result = risky_operation() catch |err| {
        zmin_log(ZMIN_LOG_ERROR, "Operation failed");
        return switch (err) {
            error.OutOfMemory => -2,
            error.InvalidInput => -3,
            else => -1,
        };
    };
    return 0;
}
```

### Memory Management

```zig
// Always clean up resources
export fn deinit() callconv(.C) void {
    if (global_cache) |cache| {
        cache.deinit();
        global_cache = null;
    }
}
```

### Compatibility

1. **Use C calling convention** for exports
2. **Avoid Zig-specific types** in interfaces
3. **Handle endianness** properly
4. **Test on multiple platforms**

## Debugging Plugins

### Debug Build

```bash
# Build plugin with debug info
zig build-lib -O Debug plugins/minifiers/my_plugin.zig

# Run with debugger
gdb --args zmin --plugin ./libmy_plugin.so input.json output.json
```

### Logging

```zig
// Use zmin logging system
export fn minify(...) callconv(.C) c_int {
    zmin_log(ZMIN_LOG_DEBUG, "Processing input");
    
    // Your code here
    
    zmin_log(ZMIN_LOG_INFO, "Minification complete");
    return 0;
}
```

## Plugin Registry

### Submitting Plugins

1. Create plugin following this guide
2. Add comprehensive tests and documentation
3. Submit to [zmin-plugins repository](https://github.com/hydepwns/zmin-plugins)
4. Include performance benchmarks

### Official Plugins

- **zmin-schema**: Schema-aware minification
- **zmin-sort**: Sort JSON keys
- **zmin-validate**: Enhanced validation
- **zmin-format**: Custom formatting options

For more examples and the latest plugin API, visit [zmin.droo.foo/plugins](https://zmin.droo.foo/plugins).