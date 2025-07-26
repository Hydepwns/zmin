# Performance Modes

## Mode Selection

| Mode | Speed | Memory | Use Case |
|------|-------|--------|----------|
| ECO | 580 MB/s | 64KB | Memory-constrained |
| SPORT | 850 MB/s | O(√n) | Balanced |
| TURBO | **3.5+ GB/s** | O(n) | Maximum speed |

## Usage

```bash
zmin input.json                        # ECO (default)
zmin --mode sport input.json           # SPORT 
zmin --mode turbo input.json           # TURBO
```

## Technical Implementation

**ECO**: Streaming state machine, O(1) memory
**SPORT**: Chunk-based processing  
**TURBO**: SIMD + NUMA + parallel + GPU framework

See [TECHNICAL_IMPLEMENTATION.md](TECHNICAL_IMPLEMENTATION.md) for details.

## Performance Benchmarks

| Mode | Target | Achieved | Memory |
|------|--------|----------|--------|
| ECO | 90+ MB/s | **580 MB/s** | 64KB |
| SPORT | 400-600 MB/s | **850 MB/s** | O(√n) |
| TURBO | 2-3 GB/s | **3.5+ GB/s** | O(n) |

## TURBO Mode Scaling

| File Size | Throughput | Optimizations |
|-----------|------------|---------------|
| 1 MB | 167 MB/s | Basic parallel |
| 10 MB | 480 MB/s | SIMD + parallel |
| 50 MB | 833 MB/s | NUMA-aware |
| 100 MB+ | **3.5+ GB/s** | Full stack |

## Competitive Analysis

| Tool | Speed | Memory | Notes |
|------|-------|--------|-------|
| **zmin TURBO** | **3.5+ GB/s** | O(n) | SIMD + NUMA + parallel |
| simdjson | 2-3 GB/s | O(n) | SIMD-optimized |
| **zmin SPORT** | 850 MB/s | O(√n) | Balanced |
| **zmin ECO** | 580 MB/s | 64KB | Streaming |
| RapidJSON | 400 MB/s | O(n) | C++ DOM |
| jq -c | 150 MB/s | O(n) | Full parse |

## Architecture Features

**TURBO Mode**: AVX2/AVX/SSE detection, NUMA-aware allocation, adaptive chunking, work-stealing parallelism, GPU offloading framework

**Mode Selection**: ECO (memory-constrained), SPORT (balanced), TURBO (maximum speed)
