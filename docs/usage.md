# Usage Guide

This comprehensive guide covers all features and usage patterns of zmin.

## Command Line Interface

### Basic Syntax

```bash
zmin [OPTIONS] [INPUT] [OUTPUT]
```

### Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--mode` | `-m` | Processing mode (eco/sport/turbo) | sport |
| `--verbose` | `-v` | Enable verbose output | false |
| `--quiet` | `-q` | Suppress all output | false |
| `--threads` | `-t` | Number of threads (turbo mode) | auto |
| `--help` | `-h` | Show help message | - |
| `--version` | `-V` | Show version information | - |
| `--validate` | | Validate JSON without minifying | false |
| `--stats` | | Show performance statistics | false |

### Input/Output Methods

#### File to File

```bash
zmin input.json output.json
```

#### Stdin to Stdout

```bash
echo '{"hello": "world"}' | zmin
cat large-file.json | zmin > minified.json
```

#### File to Stdout

```bash
zmin input.json
zmin input.json -
```

#### Stdin to File

```bash
cat input.json | zmin - output.json
```

## Processing Modes

### ECO Mode

Optimized for minimal memory usage (64KB limit):

```bash
# Perfect for embedded systems
zmin --mode eco sensor-data.json minified.json

# Memory usage stays under 64KB
zmin -m eco --stats large-file.json output.json
```

**Use cases:**

- Embedded systems
- Memory-constrained environments
- IoT devices
- Real-time processing

### SPORT Mode (Default)

Balanced performance and memory usage:

```bash
# Default mode, no flag needed
zmin data.json minified.json

# Explicitly specify sport mode
zmin --mode sport data.json minified.json
```

**Use cases:**

- General purpose minification
- Web servers
- API responses
- Configuration files

### TURBO Mode

Maximum performance using all CPU cores:

```bash
# Automatic thread detection
zmin --mode turbo huge-dataset.json output.json

# Specify thread count
zmin -m turbo -t 8 large-file.json minified.json

# View performance stats
zmin -m turbo --stats --verbose big-data.json output.json
```

**Use cases:**

- Large datasets (>100MB)
- Batch processing
- Build pipelines
- Data warehouses

## Advanced Features

### JSON Validation

Validate without minifying:

```bash
# Check if JSON is valid
zmin --validate input.json

# Exit codes:
# 0 - Valid JSON
# 1 - Invalid JSON
# 2 - File not found
# 3 - Other errors
```

### Performance Statistics

```bash
# Basic stats
zmin --stats input.json output.json

# Detailed stats with verbose mode
zmin --stats --verbose input.json output.json

# Sample output:
# ═══════════════════════════════════════
# zmin Performance Report
# ═══════════════════════════════════════
# Mode:              TURBO
# Threads:           8
# Input Size:        1.23 GB
# Output Size:       897 MB
# Compression:       27.1%
# Processing Time:   1.13s
# Throughput:        1.09 GB/s
# Memory Peak:       128 MB
# ═══════════════════════════════════════
```

### Batch Processing

Process multiple files efficiently:

```bash
#!/bin/bash
# batch-minify.sh

# Create output directory
mkdir -p minified

# Process all JSON files
for file in *.json; do
    echo "Processing $file..."
    zmin --mode turbo "$file" "minified/$file"
done

# Show summary
echo "Minified $(ls minified/*.json | wc -l) files"
```

### Pipeline Integration

Use in data pipelines:

```bash
# With curl
curl -s https://api.example.com/data | zmin > data.json

# With jq
cat data.json | jq '.results[]' | zmin > filtered.json

# In a pipeline
generate-json | zmin | gzip > data.json.gz
```

## Library Usage

### Basic Example

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Simple minification
    const input = "{  \"hello\"  :  \"world\"  }";
    const output = try zmin.minify(allocator, input);
    defer allocator.free(output);
    
    std.debug.print("{s}\n", .{output}); // {"hello":"world"}
}
```

### Mode Selection

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn processWithMode(allocator: std.mem.Allocator, json: []const u8) ![]u8 {
    // Use specific mode
    const output = try zmin.minifyWithMode(
        allocator,
        json,
        .turbo // or .eco, .sport
    );
    
    return output;
}
```

### Error Handling

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn safeMinify(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const result = zmin.minify(allocator, input) catch |err| {
        switch (err) {
            error.InvalidJson => {
                std.debug.print("Invalid JSON: {s}\n", .{input});
                return err;
            },
            error.OutOfMemory => {
                std.debug.print("Out of memory, trying ECO mode\n", .{});
                return try zmin.minifyWithMode(allocator, input, .eco);
            },
            else => return err,
        }
    };
    
    return result;
}
```

### Streaming API

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn streamMinify(reader: anytype, writer: anytype) !void {
    var minifier = zmin.StreamingMinifier.init(std.heap.page_allocator);
    defer minifier.deinit();
    
    const buffer_size = 4096;
    var buffer: [buffer_size]u8 = undefined;
    
    while (true) {
        const bytes_read = try reader.read(&buffer);
        if (bytes_read == 0) break;
        
        try minifier.process(buffer[0..bytes_read]);
        
        if (minifier.hasOutput()) {
            const output = minifier.getOutput();
            try writer.writeAll(output);
        }
    }
    
    // Flush remaining output
    try minifier.finish();
    if (minifier.hasOutput()) {
        const output = minifier.getOutput();
        try writer.writeAll(output);
    }
}
```

### Custom Allocators

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn minifyWithCustomAllocator() !void {
    // Fixed buffer allocator for embedded systems
    var buffer: [65536]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    
    const input = "{\"embedded\": true}";
    const output = try zmin.minifyWithMode(allocator, input, .eco);
    // No need to free with fixed buffer allocator
    
    std.debug.print("{s}\n", .{output});
}
```

## Performance Tips

### Choosing the Right Mode

1. **File size < 1MB**: Use SPORT mode
2. **File size > 100MB**: Use TURBO mode
3. **Memory < 256MB**: Use ECO mode
4. **Real-time processing**: Use ECO mode
5. **Batch processing**: Use TURBO mode

### Optimization Strategies

```bash
# Pre-allocate output buffer size
zmin --buffer-size 10MB large-file.json output.json

# Use memory mapping for huge files
zmin --mmap massive-dataset.json output.json

# Disable validation for trusted input
zmin --no-validate trusted-data.json output.json
```

### System Tuning

```bash
# Increase file descriptor limit
ulimit -n 4096

# Set CPU affinity for NUMA systems
numactl --cpunodebind=0 zmin --mode turbo data.json output.json

# Use huge pages
echo 1024 > /proc/sys/vm/nr_hugepages
zmin --huge-pages large-file.json output.json
```

## Integration Examples

### Node.js

```javascript
const { execSync } = require('child_process');

function minifyJson(input) {
    const result = execSync('zmin', {
        input: JSON.stringify(input),
        encoding: 'utf8'
    });
    return JSON.parse(result);
}

const data = { hello: "world", nested: { value: 42 } };
const minified = minifyJson(data);
console.log(minified);
```

### Python

```python
import subprocess
import json

def minify_json(data):
    """Minify JSON using zmin"""
    input_json = json.dumps(data)
    
    result = subprocess.run(
        ['zmin'],
        input=input_json,
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        raise Exception(f"zmin error: {result.stderr}")
    
    return json.loads(result.stdout)

# Usage
data = {"hello": "world", "array": [1, 2, 3]}
minified = minify_json(data)
print(minified)
```

### Go

```go
package main

import (
    "bytes"
    "encoding/json"
    "os/exec"
)

func minifyJSON(data interface{}) ([]byte, error) {
    input, err := json.Marshal(data)
    if err != nil {
        return nil, err
    }
    
    cmd := exec.Command("zmin")
    cmd.Stdin = bytes.NewReader(input)
    
    return cmd.Output()
}

func main() {
    data := map[string]interface{}{
        "hello": "world",
        "number": 42,
    }
    
    minified, err := minifyJSON(data)
    if err != nil {
        panic(err)
    }
    
    println(string(minified))
}
```

## Common Patterns

### Configuration File Processing

```bash
#!/bin/bash
# minify-configs.sh

# Minify all config files before deployment
find config/ -name "*.json" -exec zmin {} {}.min \;

# Replace originals
find config/ -name "*.json.min" | while read f; do
    mv "$f" "${f%.min}"
done
```

### API Response Optimization

```bash
# Nginx configuration
location /api {
    proxy_pass http://backend;
    
    # Minify JSON responses
    content_by_lua_block {
        local res = ngx.location.capture("/backend" .. ngx.var.uri)
        local handle = io.popen("zmin", "w")
        handle:write(res.body)
        local minified = handle:read("*a")
        handle:close()
        ngx.print(minified)
    }
}
```

### Build Pipeline Integration

```yaml
# GitHub Actions
- name: Minify JSON assets
  run: |
    find assets/ -name "*.json" | while read file; do
      zmin "$file" "$file.tmp"
      mv "$file.tmp" "$file"
    done
```

## Troubleshooting

### Performance Issues

```bash
# Check mode selection
zmin --verbose large-file.json output.json

# Monitor memory usage
/usr/bin/time -v zmin large-file.json output.json

# Profile CPU usage
perf record zmin --mode turbo large-file.json output.json
perf report
```

### Error Handling

```bash
# Validate JSON first
if zmin --validate input.json; then
    zmin input.json output.json
else
    echo "Invalid JSON detected"
fi

# Handle errors in scripts
if ! zmin input.json output.json 2>error.log; then
    echo "Minification failed:"
    cat error.log
fi
```
