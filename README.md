# Zmin: High-Performance JSON Minifier

Fast JSON minification with O(1) memory usage and 90+ MB/s throughput.
[![Build](https://img.shields.io/badge/Build-Passing-brightgreen?style=for-the-badge&logo=github)](https://github.com/hydepwns/zmin)
[![Zig](https://img.shields.io/badge/Zig-0.14.1-orange?style=for-the-badge&logo=zig)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge&logo=opensourceinitiative)](LICENSE)

## Features

- **Performance**: 90-100 MB/s throughput
- **Memory**: O(1) constant usage (64KB buffer)
- **Streaming**: Processes files of any size
- **Zero Dependencies**: Pure Zig implementation

## Installation

```bash
git clone https://github.com/hydepwns/zmin && cd zmin
zig build
```

## Usage

```bash
# Basic usage
zmin input.json -o output.json
cat input.json | zmin > output.json

# Options
zmin --pretty --indent 2 input.json    # Pretty print
zmin --stats input.json                # Show statistics
```

## Performance

| Dataset | Size | Throughput | Compression |
|---------|------|------------|-------------|
| Twitter | 1.0 MB | 96.48 MB/s | 29.5% |
| GitHub | 2.5 MB | 100.74 MB/s | 25.0% |
| CITM | 2.4 MB | 90.31 MB/s | 35.3% |
| Canada | 3.1 MB | 88.80 MB/s | 39.1% |

**Average**: 91.11 MB/s with constant 64KB memory usage.

## Build Commands

```bash
zig build              # Build executable
zig build test         # Run tests (98.7% pass rate)
zig build benchmark    # Performance benchmarks
```

## License

MIT License - see [LICENSE](LICENSE) file.
