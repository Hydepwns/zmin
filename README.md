# zmin - Enterprise JSON Processing Suite

[![CI Status](https://github.com/hydepwns/zmin/workflows/CI%20%26%20Testing/badge.svg)](https://github.com/hydepwns/zmin/actions)
[![Performance](https://img.shields.io/badge/performance-5%2B%20GB%2Fs-brightgreen)](docs/development/PERFORMANCE_TUNING.md)
[![Tests](https://img.shields.io/badge/tests-116%2F116%20passing-brightgreen)](https://github.com/hydepwns/zmin/actions)
[![Memory Safety](https://img.shields.io/badge/memory-zero%20leaks-green)](https://github.com/hydepwns/zmin/actions)
[![Coverage](https://img.shields.io/badge/coverage-84%25-green)](docs/development/PERFORMANCE_TUNING.md)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Zig](https://img.shields.io/badge/zig-0.14.0-orange)](https://ziglang.org)
[![ZParser](https://img.shields.io/badge/zparser-standalone%20library-blue)](https://github.com/yourusername/zparser)
[![Ecosystem](https://img.shields.io/badge/ecosystem-Python%20%7C%20Go%20%7C%20Node.js-green)](#language-bindings)

**Enterprise-grade JSON processing suite** featuring high-performance minification, streaming transformations, and a complete library ecosystem. Built for production workloads requiring **5+ GB/s throughput** with zero dependencies.

> 🚀 **NEW**: [ZParser](https://github.com/yourusername/zparser) - Standalone high-performance JSON parser library with language bindings for Python, Go, and Node.js

## 🌟 Core Features

### JSON Minifier (zmin)
- **5+ GB/s** sustained throughput with SIMD optimization
- **v2.0 transformation engine** with field filtering, schema validation, and error recovery
- **Streaming transformations** for large files and real-time processing
- **Zero dependencies** - pure Zig implementation
- **Memory safe** - comprehensive testing, zero leaks verified

### JSON Parser Library (ZParser)
- **Standalone high-performance library** extracted from zmin's core engine
- **SIMD-optimized parsing** achieving 200+ MB/s on large JSON
- **Language bindings** for Python, Go, and Node.js
- **C API** for integration with any language
- **Production-ready** with comprehensive test suites

### Cross-Platform Support
- **Platforms**: Linux, macOS, Windows (x86_64, ARM64, Apple Silicon)
- **SIMD Support**: AVX-512, AVX2, SSE2, NEON with runtime detection
- **Battle-tested**: 116/116 tests passing, zero memory leaks, 84%+ coverage

## 📦 Installation

### ZMin JSON Minifier

```bash
# From source
git clone https://github.com/hydepwns/zmin
cd zmin
zig build -Doptimize=ReleaseFast

# Package managers (coming soon)
npm install -g @zmin/cli      # CLI tool
pip install zmin              # Python bindings
go get github.com/hydepwns/zmin/go  # Go bindings
```

### ZParser JSON Library

```bash
# Clone the standalone library
git clone https://github.com/yourusername/zparser
cd zparser

# Build the core library
zig build -Doptimize=ReleaseFast

# Install language bindings
pip install ./bindings/python    # Python
cd bindings/go && go mod tidy     # Go
cd bindings/nodejs && npm install # Node.js
```

## 🌍 Language Bindings

ZParser provides native bindings for multiple programming languages:

### Python
```python
import zparser

parser = zparser.Parser()
result = parser.parse('{"name": "John", "age": 30}')
if result.success:
    print(f"Parsed {result.token_count} tokens")
    obj = parser.to_python('{"name": "John", "age": 30}')
```

### Go
```go
import "github.com/yourusername/zparser"

parser, err := zparser.NewParser()
defer parser.Close()

result, err := parser.Parse(`{"name": "John", "age": 30}`)
if result.Success {
    fmt.Printf("Parsed %d tokens\n", result.TokenCount)
}
```

### Node.js
```javascript
const zparser = require('zparser');

const parser = new zparser.Parser();
const result = parser.parse('{"name": "John", "age": 30}');
if (result.success) {
    console.log(`Parsed ${result.tokenCount} tokens`);
}
parser.destroy();
```

**Performance**: All bindings achieve **8-10x speedup** over standard libraries (json, encoding/json, JSON.parse)

## 🚀 Usage

### Command Line Interface

```bash
# Basic minification
zmin input.json output.json

# Stream processing
cat large.json | zmin > minified.json

# Advanced transformations (v2.0)
zmin input.json --filter "users.*.email,users.*.name" --output clean.json
zmin data.json --validate-schema schema.json --strict-mode
zmin logs.json --transform "timestamp,level,message" --streaming

# Multiple files with parallel processing
zmin *.json -o minified/ --parallel --turbo-mode
```

### Simple API - Basic Minification

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const input = "{ \"name\" : \"John\" , \"age\" : 30 }";
    const output = try zmin.minify(gpa.allocator(), input);
    defer gpa.allocator().free(output);

    std.debug.print("{s}\n", .{output}); // {"name":"John","age":30}
}
```

### v2.0 Transformation API

```zig
const zmin = @import("zmin");

// Field filtering
const config = zmin.v2.Config{
    .field_filter = &.{ "users.*.email", "users.*.name", "metadata.version" },
    .optimization_level = .turbo,
    .enable_schema_validation = true,
};

var transformer = try zmin.v2.Transformer.init(allocator, config);
defer transformer.deinit();

const result = try transformer.transform(input_json);
std.debug.print("Filtered JSON: {s}\n", .{result.output});
std.debug.print("Throughput: {d:.2} GB/s\n", .{result.stats.throughput_gbps});
```

### Advanced API (Fine-grained control)

```zig
const config = zmin.Config{
    .optimization_level = .aggressive,
    .memory_strategy = .pooled,
    .chunk_size = 128 * 1024,
};

var minifier = try zmin.AdvancedMinifier.init(allocator, config);
defer minifier.deinit();

const result = try minifier.minifyWithStats(input);
std.debug.print("Throughput: {d:.2} GB/s\n", .{result.stats.throughput_gbps});
```

### Streaming API (Large files)

```zig
var file = try std.fs.cwd().openFile("large.json", .{});
defer file.close();

var out = std.io.getStdOut().writer();
var minifier = try zmin.StreamingMinifier.init(out, .{});

var buffer: [8192]u8 = undefined;
while (try file.read(&buffer)) |bytes_read| {
    if (bytes_read == 0) break;
    try minifier.feedChunk(buffer[0..bytes_read]);
}
try minifier.finish();
```

## Performance

```bash
# Run benchmarks
zig build benchmark

# Typical results
small.json (1KB):      1.8 GB/s
medium.json (100KB):   3.2 GB/s  
large.json (10MB):     5.4 GB/s
huge.json (100MB):     5.7 GB/s
```

## Building

```bash
# Development build
zig build

# Optimized release
zig build -Doptimize=ReleaseFast

# Run tests
zig build test
```

## Documentation

- [API Reference](docs/api/API_REFERENCE.md)
- [Performance Guide](docs/development/PERFORMANCE_TUNING.md)
- [Architecture](docs/architecture/)
- [Examples](examples/)

## Testing

```bash
zig build test        # All tests (116/116 passing)
zig build test:fast   # Fast test suite
```

## 🏗️ Project Ecosystem

### Main Repository (zmin)
```
zmin/
├── src/                    # Core JSON processing engine
│   ├── core/              # Core minification engine
│   ├── api/               # Public APIs (Simple, Advanced, Streaming)
│   ├── v2/                # ✅ v2.0 transformation engine (COMPLETE)
│   ├── minifier/          # High-performance minification
│   ├── common/            # 🆕 Shared utilities and constants
│   └── platform/          # Platform-specific SIMD optimizations
├── examples/              # Usage examples and demos
├── tests/                 # Comprehensive test suite (116/116 passing)
├── docs/                  # Complete documentation
│   ├── api/               # API reference documentation
│   ├── architecture/      # System architecture guides
│   └── development/       # Development and performance guides
├── tools/                 # Development and benchmarking tools
├── deployments/           # Production deployment configurations
└── build/                 # Build system and packaging
```

### Extracted Libraries

#### 🆕 [ZParser](https://github.com/yourusername/zparser) - Standalone JSON Parser
```
zparser/
├── src/                   # High-performance parser core
│   ├── core/             # SIMD-optimized parsing engine
│   ├── api/              # C API for language bindings
│   └── performance/      # SIMD implementations (AVX-512, AVX2, SSE2)
├── bindings/             # ✅ Language bindings (COMPLETE)
│   ├── python/           # Python bindings with ctypes
│   ├── go/               # Go bindings with cgo
│   ├── nodejs/           # Node.js bindings with N-API
│   └── c/                # C API header and examples
├── tests/                # Comprehensive test coverage (95%+)
└── benchmarks/           # Performance benchmarking suite
```

### 🎯 Planned Extensions (ZTool Suite)
- **zpack**: MessagePack processor with JSON interop 🔄 *Next*
- **zschema**: JSON Schema validator using zparser
- **zquery**: JSONPath/JQ-like query tool
- **ztool**: Unified CLI with subcommands

### Key Technical Achievements

- **🎯 v2.0 Transformation Engine**: Field filtering, schema validation, error recovery
- **⚡ SIMD Optimization**: 200+ MB/s parsing, 5+ GB/s minification
- **🌍 Language Ecosystem**: Python, Go, Node.js bindings with 8-10x speedup
- **🏗️ Modular Architecture**: Extracted zparser as standalone library
- **📊 Production Quality**: Zero memory leaks, 84%+ test coverage, comprehensive CI/CD

## 🎉 Recent Major Achievements

### ✅ Completed (2025-08-02)

- **🚀 v2.0 Transformation Engine**: Complete streaming transformation pipeline with field filtering, schema validation, and error recovery
- **📚 ZParser Library Extraction**: Standalone high-performance JSON parser library
- **🌍 Language Bindings Ecosystem**: Python, Go, and Node.js bindings achieving 8-10x speedup
- **🏗️ Code Quality Improvements**: 15-20% code reduction through common module extraction
- **🧪 Production Readiness**: 116/116 tests passing, zero memory leaks, 84%+ coverage

### 🔄 Current Focus: Ecosystem Expansion

- **zpack MessagePack Tool** - Next priority for format conversion suite
- **Language binding distribution** - Publishing to PyPI, npm, Go modules
- **Community development** - Documentation, examples, migration guides

## 📈 Performance Benchmarks

| Component | Throughput | Improvement | Platform |
|-----------|------------|-------------|----------|
| **zmin minifier** | 5.4 GB/s | Baseline | Apple M1 Pro |
| **zparser (Python)** | 192 MB/s | 8.2x vs json | Apple M1 Pro |
| **zparser (Go)** | 244 MB/s | 10.4x vs encoding/json | Apple M1 Pro |
| **zparser (Node.js)** | 200 MB/s | 8.6x vs JSON.parse | Apple M1 Pro |

*Run `zig build benchmark` for platform-specific results*

## 🤝 Contributing

We welcome contributions to both zmin and the broader ecosystem! 

### 🎯 High-Impact Areas
- **zpack development** - MessagePack processor implementation
- **Language bindings** - New languages or binding improvements  
- **Performance optimization** - SIMD enhancements, memory management
- **Documentation** - Examples, guides, API improvements

### Development Setup

```bash
# Main zmin repository
git clone https://github.com/hydepwns/zmin
cd zmin
zig build -Doptimize=ReleaseFast
zig build test

# ZParser library (for parser development)
git clone https://github.com/yourusername/zparser
cd zparser
zig build -Doptimize=ReleaseFast
# Test language bindings
cd bindings/python && python test_zparser.py
cd ../go && go test -v
cd ../nodejs && npm test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## 📞 Community & Support

- **Documentation**: [Complete API Reference](docs/api/API_REFERENCE.md)
- **Examples**: [Usage Examples](examples/) for all components
- **Performance**: [Benchmarking Guide](docs/development/PERFORMANCE_TUNING.md)
- **Architecture**: [System Design](docs/architecture/) documentation

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**🚀 Built for enterprise-scale JSON processing with production-grade performance and reliability**
