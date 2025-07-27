# Zmin: Ultra-High-Performance JSON Minifier

A zero-dependency JSON minifier written in Zig, delivering **3.5+ GB/s** throughput with memory safety guarantees.

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/hydepwns/zmin/actions) [![Zig Version](https://img.shields.io/badge/zig-0.11-orange)](https://ziglang.org/) [![Performance](https://img.shields.io/badge/performance-3.5GB%2Fs-blue)](https://github.com/hydepwns/zmin#performance-modes) [![License](https://img.shields.io/badge/license-MIT-green)](LICENSE) [![Platforms](https://img.shields.io/badge/platforms-linux%20%7C%20macos%20%7C%20windows-lightgrey)](https://github.com/hydepwns/zmin#installation) [![Memory](https://img.shields.io/badge/memory-64KB-yellow)](https://github.com/hydepwns/zmin#performance-modes) [![SIMD](https://img.shields.io/badge/SIMD-enabled-brightgreen)](https://github.com/hydepwns/zmin#technical-implementation)

## Features

- **Ultra-high performance**: 3.5+ GB/s throughput in TURBO mode
- **Memory efficient**: ECO mode uses only 64KB memory
- **Zero dependencies**: Pure Zig implementation
- **Cross-platform**: Linux, macOS, Windows
- **Multiple language bindings**: Node.js, Go, Python
- **Three performance modes**: ECO, SPORT, TURBO
- **SIMD optimized**: Automatic CPU instruction detection
- **Memory safe**: Built with Zig's memory safety guarantees

## Installation

### From Source

```bash
git clone https://github.com/hydepwns/zmin
cd zmin
zig build
```

### Language Bindings

#### Node.js / npm

```bash
npm install @zmin/cli
```

#### Go

```bash
go get github.com/hydepwns/zmin-go
```

#### Python

```bash
pip install zmin
```

## Quick Start

### Command Line

```bash
# Basic usage
zmin input.json -o output.json

# Performance modes
zmin input.json                        # ECO (default)
zmin --mode sport input.json           # SPORT 
zmin --mode turbo input.json           # TURBO

# Pretty print
zmin --pretty input.json

# Development
zig build test && zig build benchmark  # Test & benchmark
```

### Programmatic Usage

#### Node.js

```typescript
import { minify } from '@zmin/cli';

const minified = await minify('{"key": "value"}', { mode: 'turbo' });
console.log(minified); // {"key":"value"}
```

#### Go

```go
import "github.com/hydepwns/zmin-go"

result := zmin.Minify(`{"key": "value"}`, zmin.TurboMode)
fmt.Println(result) // {"key":"value"}
```

#### Python

```python
import zmin

result = zmin.minify('{"key": "value"}', mode='turbo')
print(result)  # {"key":"value"}
```

## Performance Modes

Zmin offers three performance modes optimized for different use cases:

| Mode | Throughput | Memory Usage | Use Case | Implementation |
|------|------------|--------------|----------|----------------|
| **ECO** | 580 MB/s | 64KB | Memory-constrained environments | Streaming state machine |
| **SPORT** | 850 MB/s | O(√n) | Balanced performance/memory | Chunk-based processing |
| **TURBO** | **3.5+ GB/s** | O(n) | Maximum speed | SIMD + NUMA + parallel |

### Mode Selection Guidelines

**ECO Mode** - Choose when:

- Memory is limited (< 100MB available)
- Running in containers or embedded systems
- Processing files larger than available memory
- Need predictable memory usage

**SPORT Mode** - Choose when:

- General purpose use
- Good balance of speed and memory
- Processing medium-sized files (1-100MB)
- Running on standard systems

**TURBO Mode** - Choose when:

- Maximum speed is required
- Processing large files (> 100MB)
- Running on high-performance systems
- Have sufficient memory available

### Performance Scaling (TURBO Mode)

| File Size | Throughput | Optimizations Applied |
|-----------|------------|----------------------|
| < 1 MB | 167 MB/s | Basic parallel processing |
| 1-10 MB | 480 MB/s | SIMD + parallel |
| 10-50 MB | 833 MB/s | NUMA-aware allocation |
| 50+ MB | **3.5+ GB/s** | Full optimization stack |

## Benchmarks

| Tool | Speed | Memory | Notes |
|------|-------|--------|-------|
| **zmin TURBO** | **3.5+ GB/s** | O(n) | SIMD + NUMA + parallel |
| simdjson | 1-3 GB/s | O(n) | SIMD-optimized |
| **zmin SPORT** | 850 MB/s | O(√n) | Balanced approach |
| **zmin ECO** | 580 MB/s | 64KB | Streaming |
| RapidJSON | 399 MB/s | O(n) | C++ DOM parsing |
| jq -c | 149 MB/s | O(n) | Full JSON parsing |

## Technical Implementaton

**TURBO Mode**: AVX1/AVX/SSE detection, NUMA-aware allocation, adaptive chunking, work-stealing parallelism, GPU offloading framework

**Mode Selection**: ECO (memory-constrained), SPORT (balanced), TURBO (maximum speed)

- *ECO*: Streaming state machine, O(1) memory
- *SPORT*: Chunk-based processing  
- *TURBO*: SIMD + NUMA + parallel + GPU framework

See [docs/performance.md](docs/performance.md) for detailed implementation information.

## Contributing

We welcome contributions! Please see our [docs/PUBLISHING.md](docs/PUBLISHING.md) for development guidelines.

## License

MIT License - see [LICENSE](LICENSE) file for details.
