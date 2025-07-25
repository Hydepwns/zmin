# Zmin: High-Performance JSON Minifier

**Fast JSON minification with streaming processing and SIMD optimization**

[![Build](https://img.shields.io/badge/Build-Development-orange?style=for-the-badge&logo=zig)](https://github.com/hydepwns/zmin)
[![Zig](https://img.shields.io/badge/Zig-0.14.1-purple?style=for-the-badge&logo=zig)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge&logo=license)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platforms-Linux%7CmacOS%7CWindows-blue?style=for-the-badge&logo=platform)](https://github.com/hydepwns/zmin)

## 🚧 Current Status: In Development

Zmin is a high-performance JSON minifier written in Zig, currently in active development. The project aims to achieve world-class performance through SIMD optimization, multi-threading, and advanced algorithms.

## 🎯 Goals

- **High Performance**: Target 4+ GB/s throughput
- **Memory Efficient**: O(1) memory usage with streaming processing
- **SIMD Optimized**: CPU intrinsics for maximum performance
- **Multi-threaded**: Parallel processing for large files
- **Zero Dependencies**: Pure Zig implementation

## 🚀 Quick Start

### Installation

```bash
git clone https://github.com/hydepwns/zmin
cd zmin
zig build
```

### Basic Usage

```bash
# Build the project
zig build

# Run basic tests
zig test tests/minifier/basic.zig

# Run the application (when implemented)
zig build run
```

### API Usage (Planned)

```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{});
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const input = "{\"name\": \"John\", \"age\": 30}";
    const result = try zmin.minify(allocator, input);
    defer allocator.free(result);
    
    std.debug.print("Minified: {s}\n", .{result});
    // Output: {"name":"John","age":30}
}
```

## 🏗️ Architecture

### Core Components

1. **Basic Minifier** (`src/minifier/`)
   - Core JSON parsing and minification
   - State machine implementation
   - Basic error handling

2. **Performance Optimizations** (`src/performance/`)
   - SIMD intrinsics (planned)
   - Cache optimization (planned)
   - CPU feature detection

3. **Parallel Processing** (`src/parallel/`)
   - Multi-threading support (planned)
   - Work distribution (planned)
   - Lock-free data structures (planned)

4. **Validation & Production** (`src/validation/`, `src/production/`)
   - JSON validation (planned)
   - Error handling (planned)
   - Logging system (planned)

## 🧪 Testing

### Current Test Status

- **Basic Tests**: passing ✅
- **Extended Tests**: In development 🔄
- **Performance Tests**: Planned 📋
- **Integration Tests**: Planned 📋

### Running Tests

```bash
# Basic functionality tests
zig test tests/minifier/basic.zig

# All tests (may have dependency issues)
zig build test

# Specific test categories
zig build test:minifier
zig build test:fast
```

## 📊 Development Progress

### ✅ Implemented

- Basic JSON minifier with core functionality
- Simple test framework
- Build system structure
- Project organization

### 🔄 In Progress

- Extended test suite
- Error handling improvements
- Performance optimizations
- SIMD implementation

### 📋 Planned

- Multi-threading support
- Advanced SIMD optimizations
- Performance benchmarking
- CI/CD pipeline
- Production features

## 🛠️ Building and Development

### Build Commands

```bash
# Development build
zig build

# Optimized release build
zig build -Doptimize=ReleaseFast

# Run tests
zig build test

# Run specific test categories
zig build test:minifier
zig build test:fast
```

### Development Setup

```bash
git clone https://github.com/hydepwns/zmin
cd zmin
zig build test:minifier  # Run basic tests
```

## 📈 Performance Goals

### Target Metrics

- **Throughput**: 4+ GB/s
- **Memory Usage**: O(1) constant memory
- **SIMD Efficiency**: Significant improvement over scalar
- **Multi-threading**: Linear scaling with cores

### Current Status

- **Basic Functionality**: ✅ Working
- **Performance Optimization**: 🔄 In development
- **Benchmarking**: 📋 Planned

## 🤝 Contributing

We welcome contributions! The project is in active development and there are many areas for improvement:

1. **Fix Build Dependencies**: Resolve missing module imports
2. **Complete Test Suite**: Add comprehensive testing
3. **Performance Optimization**: Implement SIMD and threading
4. **Error Handling**: Improve robustness
5. **Documentation**: Enhance guides and examples

### Development Guidelines

- Write tests for new features
- Follow Zig coding standards
- Document complex algorithms
- Benchmark performance improvements

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🔗 Links

- [Project Structure](PROJECT_STRUCTURE.md) - Detailed architecture overview
- [Performance Goals](PERFORMANCE.md) - Performance targets and benchmarks
- [Testing Guide](tests/TESTING.md) - Comprehensive testing documentation

---

**Note**: This project is in active development. Features and performance characteristics will improve as the project matures.
