# Zmin: Ultra-High-Performance JSON Minifier

A zero-dependency JSON minifier written in Zig, delivering **GB/s throughput** with memory safety guarantees.

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/hydepwns/zmin/actions) [![Zig Version](https://img.shields.io/badge/zig-0.14.1-orange)](https://ziglang.org/) [![Performance](https://img.shields.io/badge/performance-1--3GB%2Fs-blue)](https://github.com/hydepwns/zmin#performance) [![License](https://img.shields.io/badge/license-MIT-green)](LICENSE) [![Platforms](https://img.shields.io/badge/platforms-linux%20%7C%20macos%20%7C%20windows-lightgrey)](https://github.com/hydepwns/zmin#installation)

## Features

- **Ultra-high performance**: Multi-GB/s throughput
- **Memory efficient**: Streaming architecture
- **Zero dependencies**: Pure Zig implementation
- **Cross-platform**: Linux, macOS, Windows (x64 + ARM64)
- **Language bindings**: Node.js, Go, Python, WebAssembly
- **Parallel processing**: Multi-threaded with work-stealing
- **SIMD optimized**: Automatic CPU feature detection
- **Memory safe**: Built with Zig's safety guarantees

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
# Basic minification
zmin input.json -o output.json

# Pretty print with custom indent
zmin --pretty --indent 4 input.json -o formatted.json

# Parallel processing
zmin --threads 8 large-file.json -o minified.json

# Pipe from stdin
cat data.json | zmin > minified.json

# Show statistics
zmin --stats input.json -o output.json
```

### Programmatic Usage

<details>
<summary><b>Node.js</b></summary>

```typescript
import { minify } from '@zmin/cli';

// Basic minification
const result = await minify('{"key": "value"}');

// With options
const formatted = await minify(jsonString, { 
  pretty: true, 
  indent: 2 
});
```
</details>

<details>
<summary><b>Go</b></summary>

```go
import "github.com/hydepwns/zmin-go"

// Basic minification
result := zmin.Minify(`{"key": "value"}`)

// With options
formatted := zmin.MinifyWithOptions(jsonString, &zmin.Options{
    Pretty: true,
    Indent: 2,
})
```
</details>

<details>
<summary><b>Python</b></summary>

```python
import zmin

# Basic minification
result = zmin.minify('{"key": "value"}')

# With options
formatted = zmin.minify(json_string, pretty=True, indent=2)
```
</details>

## Performance

Zmin automatically optimizes for your hardware and file size:

| File Size | Typical Throughput | Optimizations |
|-----------|-------------------|---------------|
| < 1 MB | 150-200 MB/s | Single-threaded streaming |
| 1-10 MB | 400-600 MB/s | Parallel chunking |
| 10-50 MB | 800 MB/s - 1 GB/s | SIMD + parallel |
| 50+ MB | **1-3 GB/s** | Full optimization stack |

### Resource Usage

- **Memory**: Scales with file size (streaming for small files, buffered for large)
- **CPU**: Automatic thread scaling based on available cores
- **I/O**: Zero-copy where possible, memory-mapped for large files

## Benchmarks

| Tool | Speed | Memory | Notes |
|------|-------|--------|-------|
| **zmin** | **1-3 GB/s** | Adaptive | SIMD + parallel processing |
| simdjson | 1-3 GB/s | O(n) | SIMD-optimized C++ |
| RapidJSON | 300-400 MB/s | O(n) | C++ DOM parsing |
| jq -c | 100-150 MB/s | O(n) | Full JSON parsing |
| json-minify | 50-100 MB/s | O(n) | Node.js implementation |

## Technical Implementation

- **SIMD Optimization**: AVX2/AVX/SSE automatic detection and fallback
- **Parallel Processing**: Work-stealing thread pool with adaptive chunking
- **Memory Management**: Zero-copy streaming for small files, memory-mapped for large
- **Parser Design**: State machine with lookup tables for fast character classification
- **Architecture**: Modular design with separate tokenizer, validator, and writer stages

See [docs/](docs/) for detailed documentation.

## Contributing

We welcome contributions! Please see our [docs/PUBLISHING.md](docs/PUBLISHING.md) for development guidelines.

## License

MIT License - see [LICENSE](LICENSE) file for details.
