# zmin

High-performance JSON minifier written in Zig. **1-3 GB/s throughput**.

[![Docs](https://img.shields.io/badge/docs-interactive-purple)](https://hydepwns.github.io/zmin/) [![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/hydepwns/zmin/actions) [![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Features

- **Fast**: 1-3 GB/s throughput with SIMD optimization
- **Safe**: Memory-safe Zig implementation  
- **Cross-platform**: Linux, macOS, Windows (x64 + ARM64)
- **Language bindings**: C, Node.js, Go, Python, WebAssembly
- **Zero dependencies**: No external dependencies

## Quick Start

```bash
# Build from source
git clone https://github.com/hydepwns/zmin
cd zmin && zig build

# Basic usage
./zig-out/bin/zmin input.json output.json

# Language bindings
npm install @zmin/cli              # Node.js
go get github.com/hydepwns/zmin-go # Go  
pip install zmin                   # Python
```

## Usage

```bash
# CLI options
zmin input.json output.json           # Basic minification
zmin --mode turbo large.json out.json # High performance mode
echo '{"a": 1}' | zmin                # Pipe support
```

```javascript
// Node.js
import { minify } from '@zmin/cli';
const result = await minify('{"key": "value"}');
```

```python
# Python
import zmin
result = zmin.minify('{"key": "value"}')
```

## Performance

| File Size | Throughput | Mode |
|-----------|------------|------|
| < 1 MB | 150-200 MB/s | Single-threaded |
| 1-50 MB | 400-800 MB/s | Parallel |
| 50+ MB | **1-3 GB/s** | SIMD + parallel |

**vs other tools**: 2-10x faster than jq, json-minify, RapidJSON

## Documentation

- **[Interactive API Docs](https://hydepwns.github.io/zmin/)** - Live testing + examples
- **[Getting Started](docs/getting-started.md)** - Installation guide  
- **[Performance Guide](docs/performance.md)** - Benchmarks & optimization

## License

MIT
