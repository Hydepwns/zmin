# zmin

> Currently in active development-- do not use in production! Wait for tagged 1.0.0 version and binary is released.
>
> Currently: Debugging performance improvements for mainnet release

High-performance JSON minifier written in Zig. **Up to 1.11 GB/s throughput** with GPU acceleration and advanced optimization modes.

[![Docs](https://img.shields.io/badge/docs-interactive-purple)](https://zmin.droo.foo/) [![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/hydepwns/zmin/actions) [![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Features

- **Ultra-Fast**: Up to 1.11 GB/s throughput with SIMD + GPU acceleration
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

# Language bindings
npm install @zmin/cli                    # Node.js
go get github.com/hydepwns/zmin/go       # Go
pip install zmin                         # Python
```

## Usage

### CLI Options

```bash
# Basic minification
zmin input.json output.json

# Performance modes
zmin --mode turbo large.json out.json    # Maximum throughput
zmin --mode sport medium.json out.json   # Balanced performance/memory
zmin --mode eco small.json out.json      # Memory efficient

# GPU acceleration
zmin --gpu cuda large.json out.json      # NVIDIA GPU
zmin --gpu opencl large.json out.json    # OpenCL GPU

# Advanced options
zmin --chunk-size 1MB --threads 16 large.json out.json
zmin --validate --format-check input.json out.json
echo '{"a": 1}' | zmin                    # Pipe support
```

### API Usage

```javascript
// Node.js
const { minify } = require('@zmin/cli');
const result = minify('{"key": "value"}');
```

```python
# Python
import zmin
result = zmin.minify('{"key": "value"}', mode='turbo')
```

```zig
// Zig
const zmin = @import("zmin");
const result = try zmin.minify(input, .{ .mode = .turbo });
```

## Performance Modes

| Mode | Use Case | Throughput | Memory Usage |
|------|----------|------------|--------------|
| **Eco** | Small files, low memory | ~312 MB/s | Minimal |
| **Sport** | Balanced performance | ~555 MB/s | Moderate |
| **Turbo** | Large files, max speed | **~1.11 GB/s** | Higher |

**Not sure which mode to use?** Check our [interactive mode selector](https://zmin.droo.foo/mode-selection)!

### GPU Acceleration

- **CUDA**: NVIDIA GPUs for massive datasets (2-5x CPU speed)
- **OpenCL**: Cross-platform GPU acceleration
- **Auto-detection**: Automatically selects best available GPU

## Advanced Features

### Plugin System

```zig
// Custom minification plugin
pub const MyPlugin = struct {
    pub fn transform(input: []const u8) ![]const u8 {
        // Custom transformation logic
        return result;
    }
};
```

### Development Tools

- **Hot Reloading**: Live code updates during development
- **Debugger**: Advanced debugging with breakpoints and inspection
- **Profiler**: Performance profiling and bottleneck detection
- **Validator**: JSON validation and format checking

### Parallel Processing

- **NUMA-aware**: Optimized for multi-socket systems
- **Work-stealing**: Dynamic load balancing
- **Adaptive chunking**: Optimal chunk sizes for different data
- **Streaming**: Memory-efficient processing of large files

## Performance

| File Size | Throughput | Mode | Hardware |
|-----------|------------|------|----------|
| < 1 MB | ~312 MB/s | Eco | Single-threaded |
| 1-50 MB | ~555 MB/s | Sport | Parallel |
| 50+ MB | **~1.11 GB/s** | Turbo | SIMD + parallel |
| 100+ MB | **~2.0 GB/s** | GPU | CUDA/OpenCL |

**vs other tools**: 2-10x faster than jq, json-minify, RapidJSON

## Development

### Building

```bash
# Standard build
zig build

# Development build with tools
zig build -Ddev-tools=true

# GPU support
zig build -Dgpu=cuda
zig build -Dgpu=opencl

# Cross-compilation
zig build -Dtarget=x86_64-windows-gnu
```

### Testing

```bash
# Run all tests
zig build test

# Run specific test suites
zig build test-minifier
zig build test-modes
zig build test-gpu

# Performance benchmarks
zig build benchmark
```

### Development Tools

zmin includes a comprehensive suite of development tools for JSON processing workflows:

#### Installation

**From Release (Recommended)**:

```bash
# Download and install latest release
curl -L https://github.com/hydepwns/zmin/releases/latest/download/zmin-dev-tools-linux-x86_64.tar.gz | tar -xz
cd zmin-dev-tools-*
./install.sh
```

**From Source**:

```bash
# Build all dev tools
zig build tools

# Individual tools are available in zig-out/bin/
ls zig-out/bin/  # Lists: debugger, dev-server, profiler, etc.
```

#### Available Tools

| Tool | Purpose | Usage |
|------|---------|-------|
| **debugger** | Performance analysis & debugging | `debugger -i data.json --benchmark 50` |
| **dev-server** | Development server with REST API | `dev-server 8080` |
| **profiler** | Performance profiling | `profiler --input data.json --modes eco,sport,turbo` |
| **config-manager** | Configuration management | `config-manager --show-config` |
| **plugin-registry** | Plugin discovery & management | `plugin-registry discover` |
| **hot-reloading** | File watching & auto-reload | `hot-reloading --watch "*.json"` |

#### Quick Start with Dev Tools

```bash
# 1. Start development server
dev-server 8080 &

# 2. Analyze performance across all modes
echo '{"users": [{"id": 1, "name": "John"}]}' > test.json
debugger -i test.json --benchmark 100

# 3. Profile specific modes
profiler --input test.json --modes eco,sport,turbo

# 4. Discover available plugins
plugin-registry discover

# 5. Set up file watching
hot-reloading --watch "*.json" --exec "zmin {file}"
```

#### Development Server API

The dev-server provides REST endpoints for integration:

```bash
# Start server
dev-server 8080

# Minify via API
curl -X POST http://localhost:8080/api/minify \
  -H "Content-Type: application/json" \
  -d '{"input": "{\"test\": true}", "mode": "sport"}'

# Get performance metrics
curl http://localhost:8080/api/metrics

# System information
curl http://localhost:8080/api/system
```

#### Configuration

Create `zmin.config.json` for custom settings:

```json
{
  "dev_server": {
    "port": 8080,
    "host": "localhost",
    "enable_debugging": true
  },
  "debugger": {
    "debug_level": "basic",
    "enable_profiling": true,
    "benchmark_iterations": 50
  },
  "profiler": {
    "output_dir": "./profiles",
    "enable_cpu_profiling": true,
    "enable_memory_profiling": true
  }
}
```

## Documentation

- **[Interactive API Docs](https://zmin.droo.foo/)** - Live testing + examples
- **[Getting Started](https://zmin.droo.foo/getting-started)** - Installation guide
- **[Performance Guide](https://zmin.droo.foo/performance)** - Benchmarks & optimization
- **[Usage Guide](https://zmin.droo.foo/usage)** - Advanced features and CLI options
- **[API Reference](https://zmin.droo.foo/api-reference)** - Complete API documentation

### Advanced Topics

- **[Mode Selection](https://zmin.droo.foo/mode-selection)** - Interactive guide to choose the right mode
- **[Plugin Development](https://zmin.droo.foo/plugins)** - Creating custom plugins
- **[GPU Acceleration](https://zmin.droo.foo/gpu)** - CUDA and OpenCL usage
- **[Integrations](https://zmin.droo.foo/integrations)** - Real-world examples
- **[Tool Comparisons](https://zmin.droo.foo/comparisons)** - vs jq, json-minify, etc.
- **[Troubleshooting](https://zmin.droo.foo/troubleshooting)** - Common issues & solutions

## Project Structure

```
zmin/
├── src/              # Core Zig source code
│   ├── minifier/     # JSON minification engine
│   ├── modes/        # Eco, Sport, Turbo implementations
│   ├── parallel/     # Multi-threading & work-stealing
│   ├── performance/  # SIMD, NUMA, memory optimization
│   ├── gpu/          # CUDA and OpenCL acceleration
│   └── bindings/     # C API for language bindings
├── tests/            # Comprehensive test suite
│   ├── unit/         # Unit tests
│   ├── integration/  # Integration tests
│   ├── benchmarks/   # Performance benchmarks
│   └── helpers/      # Test utilities
├── dev-tools/        # Development utilities
│   ├── debugger.zig  # Performance debugging
│   ├── profiler.zig  # Profiling & benchmarking
│   └── dev_server.zig # Development server
├── scripts/          # Build & automation scripts
│   ├── build/        # Build-related scripts
│   ├── ci/           # CI/CD automation
│   └── packaging/    # Distribution packaging
├── bindings/         # Language bindings
│   ├── nodejs/       # Node.js integration
│   ├── python/       # Python integration
│   └── go/           # Go integration
├── examples/         # Usage examples
├── benchmarks/       # Performance test datasets
├── docs/            # Technical documentation
└── website/         # Documentation website
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite: `zig build test`
6. Submit a pull request

## License

MIT

# Test workflow trigger
