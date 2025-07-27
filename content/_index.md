---
title: "zmin"
date: 2024-01-01
draft: false
---

# zmin

High-performance JSON minifier written in Zig. **Over 3 GB/s throughput** with GPU acceleration and advanced optimization modes.

## Features

- **Ultra-Fast**: Up to 1.1 GB/s throughput with SIMD + GPU acceleration
- **Multiple Modes**: Eco, Sport, and Turbo modes for different use cases
- **GPU Acceleration**: CUDA and OpenCL support for massive datasets
- **Plugin System**: Extensible architecture with custom minification plugins
- **Advanced Parallelism**: NUMA-aware work-stealing with adaptive chunking
- **Memory Safe**: Memory-safe Zig implementation with comprehensive error handling
- **Cross-platform**: Linux, macOS, Windows (x64 + ARM64)
- **Language Bindings**: C, Node.js, Go, Python, WebAssembly
- **Development Tools**: Hot reloading, debugging, profiling, and validation tools
- **Zero Dependencies**: No external dependencies

## Quick Start

```bash
# Build from source
git clone https://github.com/hydepwns/zmin
cd zmin && zig build --release=fast

# Basic usage
./zig-out/bin/zmin input.json output.json

# High-performance modes
./zig-out/bin/zmin --mode turbo large.json out.json    # Maximum speed
./zig-out/bin/zmin --mode sport medium.json out.json   # Balanced performance
./zig-out/bin/zmin --mode eco small.json out.json      # Memory efficient

# GPU acceleration (if available)
./zig-out/bin/zmin --gpu cuda large.json out.json
./zig-out/bin/zmin --gpu opencl large.json out.json
```

## Performance Modes

| Mode | Use Case | Throughput | Memory Usage |
|------|----------|------------|--------------|
| **Eco** | Small files, low memory | ~312 MB/s | Minimal |
| **Sport** | Balanced performance | ~555 MB/s | Moderate |
| **Turbo** | Large files, max speed | **~1.1 GB/s** | Higher |

[Get Started →](/docs/getting-started/)
