# Getting Started with zmin

This guide will help you get up and running with zmin quickly.

## What is zmin?

zmin is a high-performance JSON minifier written in Zig. It removes unnecessary whitespace and formatting from JSON files while preserving data integrity, making files smaller and faster to transmit.

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

- Read the [Usage Guide](usage.md) for advanced features
- Check the [Performance Guide](performance.md) for optimization tips
- See the [API Reference](api-reference.md) for library documentation
- Learn about the [Architecture](architecture.md) for technical details

## Getting Help

- Run `zmin --help` for command-line options
- Check [Troubleshooting](troubleshooting.md) for common issues
