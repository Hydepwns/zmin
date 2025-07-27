# zmin Documentation

High-performance JSON minifier documentation.

## Quick Links

- **[Interactive API Docs](https://hydepwns.github.io/zmin/)** - Live testing + examples
- [Getting Started](getting-started.md) - Installation & basic usage
- [Usage Guide](usage.md) - Advanced features
- [Performance Guide](performance.md) - Optimization & benchmarks

## Modes

- **ECO**: Memory-efficient (64KB limit)
- **SPORT**: Balanced (default)
- **TURBO**: Maximum performance

## Example

```bash
zig build --release=fast
./zig-out/bin/zmin --mode turbo input.json output.json
```
