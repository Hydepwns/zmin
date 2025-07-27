# zmin Documentation

Welcome to the zmin documentation! This guide covers everything you need to know about using zmin, the high-performance JSON minifier.

## Table of Contents

- [Getting Started](getting-started.md)
- [Installation](installation.md)
- [Usage Guide](usage.md)
- [OpenAPI Reference](api-reference.yaml)
- [Performance Guide](performance.md)
- [Architecture](architecture.md)
- [Contributing](contributing.md)
- [Troubleshooting](troubleshooting.md)

## Quick Start

```bash
# Install zmin
zig build --release=fast

# Minify a JSON file
./zig-out/bin/zmin input.json output.json

# Use different modes
./zig-out/bin/zmin --mode turbo large-file.json minified.json
```

## Processing Modes

zmin offers three processing modes optimized for different scenarios:

- **ECO Mode**: Memory-efficient mode with 64KB limit, perfect for embedded systems
- **SPORT Mode**: Balanced mode for general use, handles most files efficiently
- **TURBO Mode**: Maximum performance mode using all available CPU cores

## Key Features

- ⚡ Extremely fast JSON minification (1GB/s+ on modern hardware)
- 🔧 Multiple processing modes for different use cases
- 🧵 Parallel processing with work-stealing scheduler
- 🛡️ Memory-safe with comprehensive error handling
- 📊 NUMA-aware optimization for multi-socket systems
- 🔍 Extensive testing including fuzz testing
- 📈 Performance monitoring and profiling tools

## Documentation Structure

- **Getting Started**: Quick introduction and basic usage
- **Installation**: Detailed installation instructions for all platforms
- **Usage Guide**: Comprehensive guide to all features
- **API Reference**: Complete API documentation for library usage
- **Performance Guide**: Optimization tips and benchmarks
- **Architecture**: Deep dive into zmin's design
- **Contributing**: Guidelines for contributors
- **Troubleshooting**: Common issues and solutions