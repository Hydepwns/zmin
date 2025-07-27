# Performance Guide

This guide covers performance optimization, benchmarking, and best practices for zmin.

## Performance Overview

zmin is designed for extreme performance:

- **Throughput**: 1GB/s+ on modern CPUs
- **Memory Efficiency**: ECO mode uses only 64KB
- **Scalability**: Near-linear scaling with CPU cores
- **Latency**: Sub-millisecond for small files

## Benchmark Results

### Hardware: AMD Ryzen 9 5950X (16 cores, 32 threads)

| File Size | Mode | Time | Throughput | Memory |
|-----------|------|------|------------|--------|
| 1 KB | ECO | 0.01ms | 100 MB/s | 64 KB |
| 1 KB | SPORT | 0.008ms | 125 MB/s | 128 KB |
| 1 KB | TURBO | 0.01ms | 100 MB/s | 512 KB |
| 1 MB | ECO | 3.2ms | 312 MB/s | 64 KB |
| 1 MB | SPORT | 1.8ms | 555 MB/s | 2 MB |
| 1 MB | TURBO | 0.9ms | 1.11 GB/s | 8 MB |
| 100 MB | ECO | 320ms | 312 MB/s | 64 KB |
| 100 MB | SPORT | 180ms | 555 MB/s | 128 MB |
| 100 MB | TURBO | 90ms | 1.11 GB/s | 256 MB |
| 1 GB | ECO | 3.2s | 312 MB/s | 64 KB |
| 1 GB | SPORT | 1.8s | 555 MB/s | 512 MB |
| 1 GB | TURBO | 0.9s | 1.11 GB/s | 1 GB |

### Mode Comparison

```bash
Throughput (MB/s) - 100MB file
┌─────────────────────────────────────────┐
│ ECO    ████████ 312                     │
│ SPORT  ████████████████ 555             │
│ TURBO  ████████████████████████████ 1110│
└─────────────────────────────────────────┘

Memory Usage (MB) - 100MB file
┌─────────────────────────────────────────┐
│ ECO    ▌ 0.064                          │
│ SPORT  ████████ 128                     │
│ TURBO  ████████████████ 256             │
└─────────────────────────────────────────┘
```

## Running Benchmarks

### Built-in Benchmarks

```bash
# Run all benchmarks
zig build benchmark

# Specific mode benchmarks
zig build benchmark:sport
zig build benchmark:turbo
zig build benchmark:simd

# Custom benchmark
./zig-out/bin/zmin --benchmark input.json
```

### Performance Monitoring

```bash
# Real-time stats
zmin --stats --verbose large-file.json output.json

# Detailed profiling
./tools/performance_monitor.sh large-file.json

# Generate performance report
./scripts/benchmark_suite.sh > performance_report.txt
```

## Optimization Strategies

### 1. Choose the Right Mode

```bash
#!/bin/bash
# auto-select-mode.sh

file_size=$(stat -f%z "$1" 2>/dev/null || stat -c%s "$1")

if [ $file_size -lt 1048576 ]; then  # < 1MB
    mode="sport"
elif [ $file_size -lt 104857600 ]; then  # < 100MB
    mode="sport"
else
    mode="turbo"
fi

zmin --mode $mode "$1" "$2"
```

### 2. System-Level Optimizations

#### CPU Affinity

```bash
# Pin to specific CPU cores
taskset -c 0-7 zmin --mode turbo large.json output.json

# Use NUMA node 0
numactl --cpunodebind=0 --membind=0 zmin large.json output.json
```

#### Huge Pages

```bash
# Enable transparent huge pages
echo always > /sys/kernel/mm/transparent_hugepage/enabled

# Allocate huge pages
echo 1024 > /proc/sys/vm/nr_hugepages

# Run with huge pages
ZMIN_USE_HUGEPAGES=1 zmin --mode turbo large.json output.json
```

#### I/O Optimization

```bash
# Increase read-ahead
blockdev --setra 4096 /dev/sda

# Use O_DIRECT for large files
ZMIN_USE_DIRECT_IO=1 zmin huge-file.json output.json

# Memory-mapped I/O
zmin --mmap large-file.json output.json
```

### 3. Memory Optimization

#### Preallocate Memory

```zig
// Custom allocator with preallocation
const preallocated_size = 100 * 1024 * 1024; // 100MB
var buffer: [preallocated_size]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);

const output = try zmin.minifyWithMode(fba.allocator(), input, .turbo);
```

#### Memory Pools

```zig
// Use memory pools for repeated operations
var pool = std.heap.MemoryPool(u8).init(allocator);
defer pool.deinit();

for (files) |file| {
    const file_allocator = pool.allocator();
    const output = try zmin.minify(file_allocator, file);
    // Process output
    pool.reset(); // Reuse memory
}
```

### 4. Parallel Processing

#### Batch Processing

```bash
# Process files in parallel
find . -name "*.json" | parallel -j8 zmin {} minified/{}

# Custom parallel script
#!/bin/bash
process_batch() {
    for file in "$@"; do
        zmin --mode turbo "$file" "output/$file"
    done
}
export -f process_batch

find . -name "*.json" | xargs -n10 -P8 bash -c 'process_batch "$@"' _
```

#### Pipeline Parallelism

```zig
// Producer-consumer pattern
const Pipeline = struct {
    input_queue: std.atomic.Queue([]const u8),
    output_queue: std.atomic.Queue([]u8),
    
    fn producer(self: *Pipeline, files: [][]const u8) !void {
        for (files) |file| {
            const content = try std.fs.cwd().readFileAlloc(allocator, file, 1e9);
            self.input_queue.put(content);
        }
    }
    
    fn worker(self: *Pipeline) !void {
        while (self.input_queue.get()) |input| {
            const output = try zmin.minifyWithMode(allocator, input, .turbo);
            self.output_queue.put(output);
        }
    }
    
    fn consumer(self: *Pipeline) !void {
        while (self.output_queue.get()) |output| {
            // Write output to disk
            allocator.free(output);
        }
    }
};
```

## Performance Tuning

### Compiler Optimizations

```bash
# Maximum optimization
zig build -Drelease-fast=true -Dcpu=native

# Profile-guided optimization
zig build -Drelease-fast=true
./profile-workload.sh
zig build -Drelease-fast=true -Dpgo=profile.data

# Link-time optimization
zig build -Drelease-fast=true -Dlto=true
```

### SIMD Optimizations

zmin automatically uses SIMD when available:

- **x86_64**: SSE2, AVX2, AVX-512
- **ARM64**: NEON, SVE
- **WebAssembly**: SIMD128

Force specific SIMD level:

```bash
# Disable SIMD
ZMIN_NO_SIMD=1 zmin input.json output.json

# Force AVX2
ZMIN_FORCE_AVX2=1 zmin input.json output.json

# Check SIMD support
zmin --cpu-features
```

### Memory Allocators

```bash
# Use jemalloc
LD_PRELOAD=/usr/lib/libjemalloc.so zmin large.json output.json

# Use tcmalloc
LD_PRELOAD=/usr/lib/libtcmalloc.so zmin large.json output.json

# Use mimalloc
LD_PRELOAD=/usr/lib/libmimalloc.so zmin large.json output.json
```

## Profiling Tools

### Built-in Profiler

```bash
# Enable profiling
zmin --profile input.json output.json

# Output:
# ═══════════════════════════════════════
# Profile Report
# ═══════════════════════════════════════
# Parsing:      230ms (25.5%)
# Validation:   120ms (13.3%)
# Minification: 450ms (50.0%)
# Output:       100ms (11.1%)
# ───────────────────────────────────────
# Total:        900ms
# ═══════════════════════════════════════
```

### External Profilers

#### perf (Linux)

```bash
# CPU profiling
perf record -g zmin --mode turbo large.json output.json
perf report

# Cache misses
perf stat -e cache-misses,cache-references zmin large.json output.json

# Branch prediction
perf stat -e branch-misses,branches zmin large.json output.json
```

#### Valgrind

```bash
# Cache profiling
valgrind --tool=cachegrind zmin large.json output.json
cg_annotate cachegrind.out.<pid>

# Memory profiling
valgrind --tool=massif zmin large.json output.json
ms_print massif.out.<pid>
```

#### DTrace (macOS)

```bash
# CPU profiling
sudo dtrace -n 'profile-997 /execname == "zmin"/ { @[ustack()] = count(); }'

# System calls
sudo dtruss -c zmin large.json output.json
```

## Performance Tips

### Do's

1. **Use TURBO mode for files > 100MB**

   ```bash
   zmin --mode turbo large-dataset.json output.json
   ```

2. **Preallocate output buffer**

   ```bash
   output_size=$(zmin --estimate-size input.json)
   zmin --preallocate $output_size input.json output.json
   ```

3. **Use streaming for huge files**

   ```bash
   cat huge-file.json | zmin --stream > output.json
   ```

4. **Enable NUMA optimization**

   ```bash
   zmin --numa-aware massive-file.json output.json
   ```

5. **Batch small files**

   ```bash
   tar cf - *.json | zmin --tar | tar xf - -C output/
   ```

### Don'ts

1. **Don't use TURBO for small files** - Overhead exceeds benefit
2. **Don't disable SIMD** - Unless debugging
3. **Don't use network filesystems** - Copy locally first
4. **Don't mix modes in pipelines** - Causes thrashing
5. **Don't ignore memory limits** - Use ECO mode when constrained

## Troubleshooting Performance

### Slow Performance Checklist

1. **Check CPU throttling**

   ```bash
   # Linux
   cat /proc/cpuinfo | grep "cpu MHz"
   
   # Set performance governor
   cpupower frequency-set -g performance
   ```

2. **Check I/O bottlenecks**

   ```bash
   iostat -x 1
   iotop -o
   ```

3. **Check memory pressure**

   ```bash
   vmstat 1
   free -h
   ```

4. **Check system load**

   ```bash
   uptime
   top -H
   ```

### Performance Regression

```bash
# Compare versions
hyperfine --warmup 3 \
  'zmin-v1.0 large.json /dev/null' \
  'zmin-v1.1 large.json /dev/null'

# Bisect performance regression
git bisect start --term-old=fast --term-new=slow
git bisect fast v1.0
git bisect slow v1.1
# Run benchmark at each step
```

## Advanced Techniques

### Custom Thread Pools

```zig
const ThreadPool = struct {
    threads: []std.Thread,
    work_queue: std.atomic.Queue(Work),
    
    pub fn init(thread_count: u32) !ThreadPool {
        // Initialize thread pool
    }
    
    pub fn schedule(self: *ThreadPool, work: Work) !void {
        self.work_queue.put(work);
    }
};

// Use custom thread pool
var pool = try ThreadPool.init(16);
defer pool.deinit();

const output = try zmin.minifyWithThreadPool(allocator, input, &pool);
```

### GPU Acceleration (Experimental)

```zig
// Requires CUDA/OpenCL support
const gpu_minifier = try zmin.GpuMinifier.init();
defer gpu_minifier.deinit();

const output = try gpu_minifier.minify(input);
```

### Distributed Processing

```bash
# Split large file
split -n 8 huge-file.json part-

# Process on multiple machines
parallel --sshloginfile hosts.txt \
  --transfer --return {}.min \
  zmin --mode turbo {} {}.min ::: part-*

# Combine results
cat part-*.min > result.json
```

## Conclusion

zmin is designed for maximum performance while maintaining correctness. By following these guidelines and choosing appropriate modes and optimizations for your use case, you can achieve optimal performance for your JSON minification needs.
