# zmin Examples

This directory contains examples demonstrating various use cases for zmin.

## Basic Examples

- [basic_usage.zig](basic_usage.zig) - Simple minification example
- [mode_selection.zig](mode_selection.zig) - Using different processing modes
- [streaming.zig](streaming.zig) - Processing large files with streaming

## Advanced Examples

- [parallel_batch.zig](parallel_batch.zig) - Batch processing multiple files

## Integration Examples

- [nodejs_binding](../bindings/nodejs/) - Node.js integration
- [python_binding](../bindings/python/) - Python integration
- [go_binding](../bindings/go/) - Go integration

## Monitoring

- [monitoring](../examples/monitoring/) - Performance monitoring examples

## Building Examples

```bash
# Build all examples
zig build examples

# Build specific example
zig build-exe examples/basic_usage.zig -lc

# Run example
./basic_usage input.json output.json
```

## Quick Start

### Basic Usage

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const input = "{  \"hello\" : \"world\"  }";
    
    const output = try zmin.minify(allocator, input);
    defer allocator.free(output);
    
    std.debug.print("Minified: {s}\n", .{output});
}
```

### Command Line

```bash
# Basic minification
zmin input.json output.json

# Use turbo mode for large files
zmin --mode turbo large.json compressed.json

# Validate without minifying
zmin --validate data.json

# Interactive mode
zmin --interactive
```
