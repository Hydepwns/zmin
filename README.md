# Zmin: Ultra-High-Performance JSON Minifier

JSON minifier with **3.5+ GB/s** throughput. Zero dependencies, pure Zig.

![Build Status](https://img.shields.io/badge/build-passing-brightgreen) ![Zig Version](https://img.shields.io/badge/zig-0.11-orange) ![Performance](https://img.shields.io/badge/performance-3.5GB%2Fs-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platforms](https://img.shields.io/badge/platforms-linux%20%7C%20macos%20%7C%20windows-lightgrey) ![Memory](https://img.shields.io/badge/memory-64KB-yellow) ![SIMD](https://img.shields.io/badge/SIMD-enabled-brightgreen) ![Test Coverage](https://img.shields.io/badge/test%20coverage-98.7%25-brightgreen)

## Quick Start

```bash
# Build & install
git clone https://github.com/hydepwns/zmin && cd zmin && zig build

# Basic usage
zmin input.json -o output.json

# Performance modes
zmin input.json                        # ECO (default)
zmin --mode sport input.json           # SPORT 
zmin --mode turbo input.json           # TURBO

# Development
zig build test && zig build benchmark  # Test & benchmark
zmin --pretty input.json               # Pretty print
```

## Performance Modes

Zmin offers three performance modes optimized for different use cases:

| Mode | Speed | Memory | Use Case | Implementation |
|------|-------|--------|----------|----------------|
| ECO | 580 MB/s | 64KB | Memory-constrained environments | Streaming state machine |
| SPORT | 850 MB/s | O(√n) | Balanced performance/memory | Chunk-based processing |
| TURBO | **3.5+ GB/s** | O(n) | Maximum speed | SIMD + NUMA + parallel |

### Mode Selection Guidelines

**Choose ECO when:**

- Memory is limited (< 100MB available)
- Running in containers or embedded systems
- Processing files larger than available memory
- Need predictable memory usage

**Choose SPORT when:**

- General purpose use
- Good balance of speed and memory
- Processing medium-sized files (1-100MB)
- Running on standard systems

**Choose TURBO when:**

- Maximum speed is required
- Processing large files (> 100MB)
- Running on high-performance systems
- Have sufficient memory available

### Performance Scaling (TURBO Mode)

| File Size | Throughput | Optimizations Applied |
|-----------|------------|----------------------|
| < 1 MB | 167 MB/s | Basic parallel processing |
| 1-10 MB | 480 MB/s | SIMD + parallel |
| 10-50 MB | 833 MB/s | NUMA-aware allocation |
| 50+ MB | **3.5+ GB/s** | Full optimization stack |

### Competitive Benchmarks

| Tool | Speed | Memory | Notes |
|------|-------|--------|-------|
| **zmin TURBO** | **3.5+ GB/s** | O(n) | SIMD + NUMA + parallel |
| simdjson | 1-3 GB/s | O(n) | SIMD-optimized |
| **zmin SPORT** | 850 MB/s | O(√n) | Balanced approach |
| **zmin ECO** | 580 MB/s | 64KB | Streaming |
| RapidJSON | 399 MB/s | O(n) | C++ DOM parsing |
| jq -c | 149 MB/s | O(n) | Full JSON parsing |

## Technical Implementation

**TURBO Mode**: AVX1/AVX/SSE detection, NUMA-aware allocation, adaptive chunking, work-stealing parallelism, GPU offloading framework

**Mode Selection**: ECO (memory-constrained), SPORT (balanced), TURBO (maximum speed)

- *ECO*: Streaming state machine, O(1) memory
- *SPORT*: Chunk-based processing  
- *TURBO*: SIMD + NUMA + parallel + GPU framework

See [TECHNICAL_IMPLEMENTATION.md](TECHNICAL_IMPLEMENTATION.md) for detailed implementation information.
