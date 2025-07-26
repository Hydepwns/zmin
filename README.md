# Zmin: Ultra-High-Performance JSON Minifier

JSON minifier with **3.5+ GB/s** throughput. Zero dependencies, pure Zig.

[![Build](badges/build.svg)](.) [![Zig](badges/zig.svg)](https://ziglang.org/) [![Performance](badges/performance.svg)](PERFORMANCE.md) [![License](badges/license.svg)](LICENSE)

## Installation & Usage

```bash
git clone https://github.com/hydepwns/zmin && cd zmin && zig build
zmin input.json -o output.json
```

**Performance modes**: ECO (580 MB/s, 64KB memory), SPORT (850 MB/s), TURBO (3.5+ GB/s)

See [PERFORMANCE.md](PERFORMANCE.md) and [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for details.
