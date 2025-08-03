# zmin Performance Tuning Guide

This guide helps you achieve maximum performance from zmin for your specific use case.

## Table of Contents
1. [Performance Overview](#performance-overview)
2. [Hardware Optimization](#hardware-optimization)
3. [Configuration Tuning](#configuration-tuning)
4. [Memory Optimization](#memory-optimization)
5. [Parallel Processing](#parallel-processing)
6. [Benchmarking](#benchmarking)
7. [Troubleshooting](#troubleshooting)

## Performance Overview

zmin achieves 5+ GB/s throughput through:
- **Adaptive Strategy Selection**: Automatically chooses optimal algorithm
- **SIMD Acceleration**: Leverages AVX-512, AVX2, and NEON
- **Parallel Processing**: Multi-threaded for large inputs
- **Memory Optimization**: Pooling and NUMA-aware allocation
- **Zero-Copy Operations**: Minimizes memory movement

### Performance Targets

| Scenario | Target Throughput | Latency |
|----------|------------------|---------|
| Small files (<10KB) | 1-2 GB/s | <10μs |
| Medium files (10KB-1MB) | 3-4 GB/s | <100μs |
| Large files (>1MB) | 5+ GB/s | <10ms/MB |
| Streaming | 4+ GB/s | Continuous |

## Hardware Optimization

### CPU Features

zmin automatically detects and uses available CPU features:

```zig
const caps = zmin.detectHardwareCapabilities();
std.debug.print("CPU: {}\n", .{caps.arch_type});
std.debug.print("SIMD: {}\n", .{caps.getBestSIMD()});
```

#### x86_64 Optimization Levels
1. **SSE2** (Baseline): All x86_64 CPUs
2. **AVX2**: Intel Haswell (2013+), AMD Zen (2017+)
3. **AVX-512**: Intel Skylake-X (2017+), Ice Lake (2019+)

#### ARM64 Features
1. **NEON**: All ARM64 CPUs
2. **SVE/SVE2**: ARM Neoverse (2021+)

### Optimal Hardware Configuration

```bash
# Disable CPU frequency scaling for consistent performance
sudo cpupower frequency-set -g performance

# Pin process to specific cores
taskset -c 0-3 ./zmin large.json

# Enable huge pages
echo 1024 > /proc/sys/vm/nr_hugepages
```

## Configuration Tuning

### Optimization Levels

```zig
// Automatic (Recommended) - Adapts to input
const config = Config{ .optimization_level = .automatic };

// Maximum Performance - All optimizations
const config = Config{ .optimization_level = .extreme };

// Low Latency - Minimal overhead
const config = Config{ .optimization_level = .basic };

// Embedded/Resource Constrained
const config = Config{ .optimization_level = .none };
```

### Memory Strategies

```zig
// Standard - General purpose
.memory_strategy = .standard

// Pooled - Many small allocations
.memory_strategy = .pooled

// NUMA-Aware - Multi-socket systems
.memory_strategy = .numa_aware

// Adaptive - Auto-selects
.memory_strategy = .adaptive
```

### Chunk Size Tuning

Optimal chunk size depends on CPU cache:

```zig
// L2 cache optimized (256KB cache)
.chunk_size = 128 * 1024

// L3 cache optimized (8MB cache)  
.chunk_size = 1024 * 1024

// Streaming optimized
.chunk_size = 64 * 1024
```

### Profile-Guided Configuration

```zig
// Analyze your workload
const profile = try zmin.profileWorkload(allocator, sample_files);

// Get recommended configuration
const config = profile.getRecommendedConfig();

std.debug.print("Recommended chunk size: {}\n", .{config.chunk_size});
std.debug.print("Recommended strategy: {}\n", .{config.memory_strategy});
```

## Memory Optimization

### Pre-allocation

```zig
// Pre-allocate based on estimated size
const estimated = zmin.estimateMinifiedSize(input);
var output = try allocator.alloc(u8, estimated);

// Use fixed buffer for small inputs
var buffer: [8192]u8 = undefined;
const result = try zmin.minifyToBuffer(input, &buffer);
```

### Arena Allocators

```zig
// Use arena for temporary allocations
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

const result = try zmin.minify(arena.allocator(), input);
// No need to free individual allocations
```

### Memory Pooling

```zig
// Create memory pool for repeated operations
var pool = try zmin.MemoryPool.init(allocator, .{
    .pool_size = 10 * 1024 * 1024, // 10MB pool
    .chunk_size = 64 * 1024,        // 64KB chunks
});
defer pool.deinit();

// Use pool for minification
for (files) |file| {
    const result = try pool.minify(file);
    processResult(result);
    pool.reset(); // Reuse memory
}
```

## Parallel Processing

### Automatic Parallelization

```zig
// Enable parallel processing for large inputs
const config = Config{
    .parallel_threshold = 1024 * 1024, // Parallelize >1MB
};
```

### Manual Thread Pool

```zig
// Create thread pool
var pool = try zmin.ThreadPool.init(allocator, .{
    .thread_count = try std.Thread.getCpuCount(),
    .queue_size = 1000,
});
defer pool.deinit();

// Process files in parallel
const results = try pool.minifyBatch(files);
```

### Parallel Streaming

```zig
// Parallel chunk processing
var processor = try zmin.ParallelProcessor.init(allocator, .{
    .worker_count = 4,
    .chunk_size = 256 * 1024,
});

try processor.processStream(input_reader, output_writer);
```

## Benchmarking

### Micro-benchmarks

```zig
// Benchmark specific operation
const result = try zmin.benchmarkOperation(allocator, .{
    .operation = .whitespace_removal,
    .input_size = 1024 * 1024,
    .iterations = 1000,
});

std.debug.print("Throughput: {d:.2} GB/s\n", .{result.throughput_gbps});
std.debug.print("Cycles/byte: {d:.2}\n", .{result.cycles_per_byte});
```

### Full Pipeline Benchmark

```zig
// Comprehensive benchmark
const bench = try zmin.Benchmark.init(allocator);
defer bench.deinit();

try bench.addFile("small.json", .small);
try bench.addFile("medium.json", .medium);
try bench.addFile("large.json", .large);

const results = try bench.run(.{
    .warmup_iterations = 10,
    .iterations = 100,
    .configurations = &.{
        Config{ .optimization_level = .basic },
        Config{ .optimization_level = .aggressive },
        Config{ .optimization_level = .extreme },
    },
});

try results.printReport(std.io.getStdOut().writer());
try results.exportCSV("benchmark_results.csv");
```

### Performance Monitoring

```zig
// Enable performance counters
var monitor = try zmin.PerformanceMonitor.init();
defer monitor.deinit();

monitor.start();
const result = try zmin.minify(allocator, input);
const stats = monitor.stop();

std.debug.print("CPU cycles: {}\n", .{stats.cpu_cycles});
std.debug.print("Cache misses: {}\n", .{stats.cache_misses});
std.debug.print("Branch mispredicts: {}\n", .{stats.branch_mispredicts});
```

## Troubleshooting

### Performance Issues

#### 1. Lower than expected throughput

Check hardware capabilities:
```zig
const caps = zmin.detectHardwareCapabilities();
if (!caps.has_avx2) {
    std.debug.print("Warning: AVX2 not available, performance limited\n", .{});
}
```

Verify optimization level:
```zig
const config = minifier.getConfig();
std.debug.print("Optimization: {}\n", .{config.optimization_level});
```

#### 2. High memory usage

Monitor allocations:
```zig
const stats = allocator.getStats();
std.debug.print("Peak memory: {} MB\n", .{stats.peak_bytes / 1024 / 1024});
```

Use streaming for large files:
```zig
var streamer = try zmin.StreamingMinifier.init(writer, .{
    .buffer_size = 64 * 1024, // Limit memory usage
});
```

#### 3. Inconsistent performance

Check for:
- CPU throttling
- Other processes competing for resources
- NUMA effects on multi-socket systems

```bash
# Monitor CPU frequency
watch -n 1 "grep MHz /proc/cpuinfo"

# Check for throttling
dmesg | grep -i throttl

# NUMA statistics
numastat
```

### Profiling

#### CPU Profiling
```bash
# Using perf
perf record -g ./zmin large.json
perf report

# Using Intel VTune
vtune -collect hotspots ./zmin large.json
```

#### Memory Profiling
```zig
// Built-in memory profiler
const profiler = try zmin.MemoryProfiler.init(allocator);
defer profiler.deinit();

const result = try profiler.profileMinification(input);
try profiler.printReport();
```

### Debug Mode

Enable detailed diagnostics:
```zig
const config = Config{
    .enable_diagnostics = true,
    .diagnostic_level = .verbose,
};

var minifier = try AdvancedMinifier.init(allocator, config);
minifier.setDiagnosticCallback(logDiagnostic);
```

## Platform-Specific Optimization

### Linux
```zig
// Enable huge pages
const config = Config{
    .memory_strategy = .numa_aware,
    .use_huge_pages = true,
};
```

### macOS (Apple Silicon)
```zig
// Optimize for unified memory
const config = Config{
    .optimization_level = .automatic,
    .apple_silicon_optimized = true,
};
```

### Windows
```zig
// Use Windows-specific features
const config = Config{
    .memory_strategy = .standard,
    .windows_large_pages = true,
};
```

## Best Practices Summary

1. **Let zmin adapt**: Use `.automatic` optimization by default
2. **Profile first**: Measure before optimizing
3. **Match workload**: Configure based on your specific use case
4. **Monitor resources**: Watch memory and CPU usage
5. **Batch operations**: Process multiple files together
6. **Use appropriate API**: Simple for basic needs, Advanced for control
7. **Consider streaming**: For large files or continuous data

## Performance Checklist

- [ ] Correct optimization level for use case
- [ ] Appropriate chunk size for cache
- [ ] Memory strategy matches allocation pattern  
- [ ] Parallel processing for large inputs
- [ ] Streaming for very large files
- [ ] Pre-allocation when size is known
- [ ] Arena allocators for temporary data
- [ ] CPU affinity for consistent performance
- [ ] Profiling data collected and analyzed
- [ ] Platform-specific optimizations enabled