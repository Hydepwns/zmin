---
title: "Getting Started"
date: 2024-01-01
draft: false
weight: 1
---

# Getting Started with zmin

Quick setup guide for zmin.

## Overview

JSON minifier that removes whitespace for smaller file sizes. 1-3 GB/s throughput.

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/hydepwns/zmin.git
cd zmin

# Build with Zig
zig build --release=fast

# The binary will be at ./zig-out/bin/zmin
```

### System Requirements

- Zig 0.14.1 or later
- 64-bit processor (x86_64 or ARM64)
- Linux, macOS, or Windows
- Minimum 64MB RAM (more for large files)

## Basic Usage

### Command Line

The simplest way to use zmin:

```bash
# Minify a JSON file
zmin input.json output.json

# Minify from stdin to stdout
echo '{"hello": "world"}' | zmin

# Specify a processing mode
zmin --mode turbo large-file.json compressed.json
```

### Processing Modes

Choose the right mode for your use case:

```bash
# ECO mode - Memory limited to 64KB
zmin --mode eco embedded-data.json minified.json

# SPORT mode - Balanced performance (default)
zmin --mode sport data.json minified.json

# TURBO mode - Maximum speed, uses all CPU cores
zmin --mode turbo huge-dataset.json minified.json
```

## Examples

### Basic Minification

Input (`data.json`):

```json
{
  "name": "John Doe",
  "age": 30,
  "city": "New York",
  "hobbies": [
    "reading",
    "coding",
    "hiking"
  ]
}
```

Command:

```bash
zmin data.json minified.json
```

Output (`minified.json`):

```json
{"name":"John Doe","age":30,"city":"New York","hobbies":["reading","coding","hiking"]}
```

### Batch Processing

Process multiple files:

```bash
# Using a shell loop
for file in *.json; do
    zmin "$file" "minified/${file}"
done

# Using parallel processing
find . -name "*.json" | parallel zmin {} minified/{}
```

### Performance Monitoring

View performance statistics:

```bash
# Enable verbose output
zmin --verbose large-file.json output.json

# Output:
# Mode: TURBO
# Input size: 1.2 GB
# Output size: 890 MB
# Compression ratio: 25.8%
# Processing time: 1.1s
# Throughput: 1.09 GB/s
```

## Library Usage

Use zmin as a library in your Zig projects:

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const input = "{\"hello\": \"world\"}";
    const output = try zmin.minify(allocator, input);
    defer allocator.free(output);

    std.debug.print("Minified: {s}\n", .{output});
}
```

## Next Steps

- Visit [zmin.droo.foo](https://zmin.droo.foo) for interactive documentation
- Read the [Usage Guide](https://zmin.droo.foo/usage) for advanced features
- Check the [Performance Guide](https://zmin.droo.foo/performance) for optimization tips
- Try the [Interactive API Docs](https://zmin.droo.foo/api-reference) for live examples

## Getting Help

- Run `zmin --help` for command-line options
- Check the [Usage Guide](usage.md) for advanced troubleshooting
