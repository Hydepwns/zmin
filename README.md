# Zmin: High-Performance JSON Minifier

Fast JSON minification with O(1) memory usage and 90+ MB/s throughput.
[![Build](https://img.shields.io/badge/Build-Passing-brightgreen?style=for-the-badge&logo=github)](https://github.com/hydepwns/zmin)
[![Zig](https://img.shields.io/badge/Zig-0.14.1-orange?style=for-the-badge&logo=zig)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge&logo=opensourceinitiative)](LICENSE)

## Features

- **Performance**: 91+ MB/s average throughput
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

See [PERFORMANCE.md](PERFORMANCE.md) for detailed benchmarks and comparative analysis.

## Quick Start

```bash
zig build              # Build executable
zig build test         # Run tests
zig build benchmark    # Performance benchmarks
```

For detailed build options, see [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md#build-system).

## License

MIT License - see [LICENSE](LICENSE) file.
