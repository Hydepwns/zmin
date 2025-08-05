# zmin - Enterprise JSON Processing Suite

[![CI Status](https://github.com/hydepwns/zmin/workflows/CI%20%26%20Testing/badge.svg)](https://github.com/hydepwns/zmin/actions)
[![Performance](https://img.shields.io/badge/performance-5%2B%20GB%2Fs-brightgreen)](docs/development/PERFORMANCE_TUNING.md)
[![Tests](https://img.shields.io/badge/tests-116%2F116%20passing-brightgreen)](https://github.com/hydepwns/zmin/actions)
[![Memory Safety](https://img.shields.io/badge/memory-zero%20leaks-green)](https://github.com/hydepwns/zmin/actions)
[![Coverage](https://img.shields.io/badge/coverage-84%25-green)](docs/development/PERFORMANCE_TUNING.md)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Zig](https://img.shields.io/badge/zig-0.14.0-orange)](https://ziglang.org)

Enterprise-grade JSON processing suite with high-performance minification, streaming transformations, and multi-language bindings. Achieves 5+ GB/s throughput with zero dependencies and memory-safe operation.

## Core Components

| Component | Throughput | Features | Status |
|-----------|------------|----------|--------|
| **zmin CLI** | 5.4 GB/s | Minification, streaming, transformations | Production |
| **ZParser Library** | 200+ MB/s | SIMD parsing, C API, language bindings | Production |
| **v2 Engine** | 5+ GB/s | Field filtering, schema validation, error recovery | Complete |

## Platform Support

| Architecture | SIMD Support | Operating Systems |
|--------------|--------------|-------------------|
| x86_64 | AVX-512, AVX2, SSE2 | Linux, macOS, Windows |
| ARM64 | NEON | Linux, macOS (Apple Silicon) |
| Runtime Detection | Automatic fallback | All supported platforms |

## Installation

### From Source
```bash
git clone https://github.com/hydepwns/zmin
cd zmin
zig build -Doptimize=ReleaseFast
```

### Language Bindings
```bash
# Python
pip install ./bindings/python

# Go  
cd bindings/go && go mod tidy

# Node.js
cd bindings/nodejs && npm install
```

## Language Bindings

### Performance Comparison

| Language | Library | Throughput | Speedup |
|----------|---------|------------|---------|
| Python | zparser | 192 MB/s | 8.2x vs json |
| Go | zparser | 244 MB/s | 10.4x vs encoding/json |
| Node.js | zparser | 200 MB/s | 8.6x vs JSON.parse |

### Usage Examples

**Python**
```python
import zparser
parser = zparser.Parser()
result = parser.parse('{"name": "John", "age": 30}')
```

**Go**
```go
import "github.com/yourusername/zparser"
parser, err := zparser.NewParser()
result, err := parser.Parse(`{"name": "John", "age": 30}`)
```

**Node.js**
```javascript
const zparser = require('zparser');
const parser = new zparser.Parser();
const result = parser.parse('{"name": "John", "age": 30}');
```

## Usage

### Command Line Interface
```bash
# Basic operations
zmin input.json output.json
cat large.json | zmin > minified.json

# v2.0 transformations
zmin input.json --filter "users.*.email,users.*.name"
zmin data.json --validate-schema schema.json --strict-mode
zmin *.json -o minified/ --parallel --turbo-mode
```

### API Overview

| API Level | Use Case | Configuration |
|-----------|----------|---------------|
| Simple | Basic minification | Default settings |
| Advanced | Fine-grained control | Custom config |
| Streaming | Large files | Chunk-based processing |
| v2.0 | Transformations | Field filtering, validation |

### Basic Usage
```zig
const zmin = @import("zmin");
const output = try zmin.minify(allocator, input);
```

### Advanced Configuration
```zig
const config = zmin.Config{
    .optimization_level = .aggressive,
    .memory_strategy = .pooled,
    .chunk_size = 128 * 1024,
};
var minifier = try zmin.AdvancedMinifier.init(allocator, config);
const result = try minifier.minifyWithStats(input);
```

### v2.0 Transformations
```zig
const config = zmin.v2.Config{
    .field_filter = &.{ "users.*.email", "users.*.name" },
    .optimization_level = .turbo,
    .enable_schema_validation = true,
};
var transformer = try zmin.v2.Transformer.init(allocator, config);
const result = try transformer.transform(input_json);
```

## Performance Benchmarks

| File Size | Throughput | Test Command |
|-----------|------------|--------------|
| 1KB | 1.8 GB/s | `zig build benchmark` |
| 100KB | 3.2 GB/s | Platform: Apple M1 Pro |
| 10MB | 5.4 GB/s | Optimization: ReleaseFast |
| 100MB | 5.7 GB/s | SIMD: Auto-detected |

## Building

| Command | Purpose |
|---------|---------|
| `zig build` | Development build |
| `zig build -Doptimize=ReleaseFast` | Optimized release |
| `zig build test` | Run test suite |
| `zig build test:fast` | Quick tests only |

## Documentation

| Resource | Description |
|----------|-------------|
| [API Reference](docs/api/API_REFERENCE.md) | Complete API documentation |
| [Performance Guide](docs/development/PERFORMANCE_TUNING.md) | Optimization techniques |
| [Architecture](docs/architecture/) | System design documents |
| [Examples](examples/) | Usage examples and demos |

## Testing

| Test Suite | Coverage | Status |
|------------|----------|--------|
| Full test suite | 84%+ | 116/116 passing |
| Fast test suite | Core functionality | Development use |
| Benchmark suite | Performance validation | Platform-specific |

## Project Architecture

### Core Repository Structure
```
src/
├── core/         # Minification engine
├── api/          # Simple, Advanced, Streaming APIs  
├── v2/           # Transformation engine (field filtering, validation)
├── minifier/     # SIMD-optimized implementations
├── parallel/     # Work-stealing, chunk processing
├── platform/     # Hardware detection, SIMD operations
└── common/       # Shared utilities, constants

build/            # Modular build system
docs/             # API reference, architecture guides
examples/         # Usage demonstrations
tests/            # Comprehensive test suite
tools/            # Development utilities
```

### Technical Achievements

| Feature | Implementation | Status |
|---------|----------------|--------|
| v2.0 Transformation Engine | Field filtering, schema validation, error recovery | Complete |
| SIMD Optimization | AVX-512, AVX2, SSE2, NEON with runtime detection | Production |
| Language Bindings | Python, Go, Node.js with 8-10x speedup | Production |
| Memory Safety | Zero leaks, comprehensive testing | Verified |
| Modular Architecture | Standalone libraries, clean interfaces | Complete |

## Contributing

### High-Impact Areas
- Performance optimization (SIMD, memory management)
- Language bindings (new languages, improvements)
- Documentation (examples, guides, API reference)
- Testing (edge cases, performance validation)

### Development Setup
```bash
git clone https://github.com/hydepwns/zmin
cd zmin
zig build -Doptimize=ReleaseFast
zig build test
```

## Support

| Resource | Location |
|----------|----------|
| API Documentation | [docs/api/](docs/api/) |
| Usage Examples | [examples/](examples/) |
| Performance Guide | [docs/development/PERFORMANCE_TUNING.md](docs/development/PERFORMANCE_TUNING.md) |
| Architecture Guide | [docs/architecture/](docs/architecture/) |

## License

MIT License - see [LICENSE](LICENSE) for details.

---

Built for enterprise-scale JSON processing with production-grade performance and reliability.
