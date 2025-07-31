---
title: "Examples"
description: "Code examples and usage patterns for zmin"
date: 2024-01-01
weight: 3
---

# Examples

This page contains practical examples of how to use zmin in different scenarios.

## Basic Usage

### Simple Minification

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const input = "{\"name\":\"John\",\"age\":30}";
    const output = try zmin.minify(allocator, input);
    defer allocator.free(output);

    std.debug.print("Minified: {s}\n", .{output});
}
```

### With Validation

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const input = "{\"name\":\"John\",\"age\":30}";

    // Validate first
    try zmin.validate(input);

    // Then minify
    const output = try zmin.minify(allocator, input);
    defer allocator.free(output);

    std.debug.print("Validated and minified: {s}\n", .{output});
}
```

## Processing Modes

### ECO Mode (Memory Limited)

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const input = "{\"large\":\"dataset\"}";
    const output = try zmin.minifyWithMode(allocator, input, .eco);
    defer allocator.free(output);

    std.debug.print("ECO mode output: {s}\n", .{output});
}
```

### SPORT Mode (Balanced)

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const input = "{\"balanced\":\"performance\"}";
    const output = try zmin.minifyWithMode(allocator, input, .sport);
    defer allocator.free(output);

    std.debug.print("SPORT mode output: {s}\n", .{output});
}
```

### TURBO Mode (Maximum Performance)

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const input = "{\"maximum\":\"speed\"}";
    const output = try zmin.minifyWithMode(allocator, input, .turbo);
    defer allocator.free(output);

    std.debug.print("TURBO mode output: {s}\n", .{output});
}
```

## File Processing

### Process a File

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Read input file
    const input_file = try std.fs.cwd().openFile("input.json", .{});
    defer input_file.close();

    const input_content = try input_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(input_content);

    // Minify
    const output = try zmin.minify(allocator, input_content);
    defer allocator.free(output);

    // Write output file
    const output_file = try std.fs.cwd().createFile("output.json", .{});
    defer output_file.close();

    try output_file.writeAll(output);
}
```

### Streaming Large Files

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const input_file = try std.fs.cwd().openFile("large.json", .{});
    defer input_file.close();

    const output_file = try std.fs.cwd().createFile("minified.json", .{});
    defer output_file.close();

    // Stream process the file
    try zmin.streamMinify(input_file, output_file, allocator, .turbo);
}
```

## Batch Processing

### Process Multiple Files

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const files = [_][]const u8{ "file1.json", "file2.json", "file3.json" };

    for (files) |filename| {
        const input_file = try std.fs.cwd().openFile(filename, .{});
        defer input_file.close();

        const input_content = try input_file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(input_content);

        const output = try zmin.minify(allocator, input_content);
        defer allocator.free(output);

        const output_filename = try std.fmt.allocPrint(allocator, "minified_{s}", .{filename});
        defer allocator.free(output_filename);

        const output_file = try std.fs.cwd().createFile(output_filename, .{});
        defer output_file.close();

        try output_file.writeAll(output);
    }
}
```

## Error Handling

### Comprehensive Error Handling

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const input = "{\"invalid\": json}";

    // Handle validation errors
    if (zmin.validate(input)) {
        std.debug.print("JSON is valid\n", .{});
    } else |err| {
        std.debug.print("Validation error: {}\n", .{err});
        return;
    }

    // Handle minification errors
    const output = zmin.minify(allocator, input) catch |err| {
        std.debug.print("Minification error: {}\n", .{err});
        return;
    };
    defer allocator.free(output);

    std.debug.print("Successfully minified: {s}\n", .{output});
}
```

## Performance Monitoring

### With Performance Metrics

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const timer = try std.time.Timer.start();
    const input = "{\"performance\":\"test\"}";

    const output = try zmin.minify(allocator, input);
    defer allocator.free(output);

    const elapsed = timer.read();
    const throughput = @as(f64, @floatFromInt(input.len)) / @as(f64, @floatFromInt(elapsed)) * 1_000_000_000;

    std.debug.print("Processed {d} MB/s\n", .{throughput / 1_000_000});
}
```

## Next Steps

- Check out the [API Reference](/api-reference-generated.html) for complete function documentation
- Read the [Performance Guide](/docs/performance/) for optimization tips
- Explore [GPU Acceleration](/docs/gpu/) for massive dataset processing
