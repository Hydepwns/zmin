# Quick Reference

## Commands

```bash
zig build && zmin input.json -o output.json  # Build & minify
zmin --mode turbo large.json -o out.json     # Max speed
zmin --pretty input.json                     # Pretty print
zig build test && zig build benchmark        # Test & benchmark
```

## Performance Modes

| Mode | Speed | Memory | Use Case |
|------|-------|--------|----------|
| ECO | 580 MB/s | 64KB | Memory-constrained |
| SPORT | 850 MB/s | O(√n) | Balanced |
| TURBO | 3.5+ GB/s | O(n) | Maximum speed |

## Documentation

- [README.md](README.md) - Installation & usage
- [PERFORMANCE.md](PERFORMANCE.md) - Benchmarks
- [tests/TESTING.md](tests/TESTING.md) - Test coverage
