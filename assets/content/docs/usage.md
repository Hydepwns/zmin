---
title: "Usage Guide"
date: 2024-01-01
draft: false
weight: 3
---

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

# Manual thread count
zmin --mode turbo --threads 16 large-file.json output.json
```

**Use cases:**

- Large datasets
- Batch processing
- High-throughput scenarios
- Server environments

## Advanced Features

### GPU Acceleration

```bash
# CUDA acceleration (NVIDIA GPUs)
zmin --gpu cuda large-file.json output.json

# OpenCL acceleration (cross-platform)
zmin --gpu opencl large-file.json output.json

# Auto-detect best GPU
zmin --gpu auto massive-dataset.json output.json
```

### Performance Monitoring

```bash
# Enable statistics
zmin --stats large-file.json output.json

# Verbose output with timing
zmin --verbose --stats huge-file.json output.json

# Output example:
# Mode: TURBO
# Input size: 2.1 GB
# Output size: 1.5 GB
# Compression ratio: 28.6%
# Processing time: 1.8s
# Throughput: 1.17 GB/s
# Memory usage: 512 MB
```

### Validation

```bash
# Validate JSON without minifying
zmin --validate input.json

# Check format and structure
zmin --validate --format-check input.json
```

## Examples

### Basic Usage

```bash
# Simple minification
zmin data.json minified.json

# Pipe from command
curl -s https://api.example.com/data.json | zmin > local.json

# Process multiple files
for file in *.json; do
    zmin "$file" "minified/${file}"
done
```

### Advanced Usage

```bash
# High-performance batch processing
find . -name "*.json" -size +1M | parallel zmin --mode turbo {} minified/{}

# GPU-accelerated processing
zmin --gpu cuda --mode turbo --stats massive-dataset.json output.json

# Memory-efficient processing
zmin --mode eco --quiet sensor-data.json embedded.json
```

## Error Handling

### Common Errors

```bash
# Invalid JSON
zmin invalid.json output.json
# Error: Invalid JSON at line 5, column 12

# File not found
zmin nonexistent.json output.json
# Error: Cannot open input file: nonexistent.json

# Permission denied
zmin input.json /root/output.json
# Error: Cannot write to output file: Permission denied
```

### Recovery Options

```bash
# Continue on errors (skip invalid files)
zmin --continue-on-error *.json minified/

# Validate before processing
zmin --validate --format-check input.json && zmin input.json output.json
```

## Integration Examples

### Shell Scripts

```bash
#!/bin/bash
# Batch minification script

INPUT_DIR="data"
OUTPUT_DIR="minified"
MODE="turbo"

mkdir -p "$OUTPUT_DIR"

for file in "$INPUT_DIR"/*.json; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "Processing $filename..."
        zmin --mode "$MODE" "$file" "$OUTPUT_DIR/$filename"
    fi
done
```

### Makefile Integration

```makefile
# Minify all JSON files
minify: $(wildcard *.json)
	@for file in $^; do \
		zmin --mode turbo "$$file" "minified/$$file"; \
	done

# Clean minified files
clean:
	rm -rf minified/
```

## Performance Tips

1. **Use appropriate modes**: ECO for small files, TURBO for large datasets
2. **Enable GPU acceleration**: 2-5x speedup for compatible hardware
3. **Batch processing**: Process multiple files together for better throughput
4. **Memory management**: Monitor memory usage for very large files
5. **Thread optimization**: Adjust thread count based on your CPU cores

## Troubleshooting

### Performance Issues

- **Slow processing**: Try TURBO mode or GPU acceleration
- **High memory usage**: Switch to ECO mode for memory-constrained environments
- **GPU not detected**: Install appropriate drivers and CUDA/OpenCL runtime

### Common Problems

- **Invalid JSON**: Use `--validate` to check input files
- **Permission errors**: Check file permissions and disk space
- **Build issues**: Ensure Zig version compatibility
