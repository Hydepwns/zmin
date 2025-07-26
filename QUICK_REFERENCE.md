# Zmin Quick Reference

## Core Documentation

- **[README.md](README.md)** - Overview, installation, basic usage
- **[PERFORMANCE.md](PERFORMANCE.md)** - Benchmarks, comparative analysis, trade-offs
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** - Architecture, components, development roadmap
- **[tests/TESTING.md](tests/TESTING.md)** - Test coverage, running tests
- **[tests/CI_CD_GUIDE.md](tests/CI_CD_GUIDE.md)** - CI/CD pipeline, tools, automation

## Common Commands

```bash
# Build & Run
zig build                    # Build zmin
zmin input.json -o out.json  # Minify JSON

# Testing
zig build test               # Run all tests
zig build benchmark          # Performance benchmarks

# Development
./scripts/test-ci.sh         # Test CI locally
zig build tools:badges       # Generate badges
```

## Key Features

- **91+ MB/s** throughput with **O(1) memory** (64KB)
- True streaming - handles files of any size
- Zero dependencies - pure Zig implementation
- 98.7% test coverage

## Performance Comparison

| Tool | Speed | Memory | Use When |
|------|-------|--------|----------|
| zmin | 91 MB/s | 64KB | Memory constrained, streaming needed |
| simdjson | 2-3 GB/s | O(n) | Maximum speed, memory available |
| jq | 150 MB/s | O(n) | Command-line manipulation |