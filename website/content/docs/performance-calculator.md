---
title: "Performance Calculator"
description: "Calculate expected performance for your specific use case"
weight: 52
---

# Performance Calculator

Use this interactive calculator to estimate zmin's performance for your specific JSON processing needs.

{{< performance-calculator >}}

## Understanding the Results

### Processing Time
The estimated time to process your JSON data, including:
- File reading
- JSON parsing and validation
- Minification
- Output writing

### Throughput
Data processing rate in GB/s, representing the speed at which zmin processes your JSON data.

### Memory Usage
Estimated peak memory consumption during processing. Actual usage may vary based on:
- JSON structure complexity
- Nesting depth
- String duplication

### Files per Second
For batch processing scenarios, this shows how many files can be processed per second.

## Factors Affecting Performance

### 1. Performance Mode
- **Eco**: Balanced performance and resource usage
- **Sport**: Optimized for speed with moderate resource use
- **Turbo**: Maximum performance with all optimizations enabled

### 2. Hardware Type
- **Laptop**: Typical dual/quad-core mobile processors
- **Desktop**: Standard desktop processors with better cooling
- **Server**: High-core-count processors with sustained performance

### 3. File Characteristics
- **Size**: Larger files benefit more from streaming
- **Structure**: Deeply nested JSON processes slower
- **Content**: Numeric-heavy JSON processes faster than string-heavy

## Real-World Performance Tips

### Batch Processing
When processing multiple files:
```bash
# Less efficient - new process per file
for file in *.json; do
    zmin "$file" > "min_$file"
done

# More efficient - single process
zmin *.json --output-dir=minified/
```

### Parallel Processing
For many files, use parallel execution:
```bash
# Process 8 files in parallel
find . -name "*.json" | parallel -j8 zmin {} -o {.}.min.json
```

### Memory vs Speed Trade-off
- Use `--streaming` for large files to reduce memory usage
- Use `--buffer-size` to tune memory/speed balance
- Enable `--gpu` for files over 100MB when available

## Benchmarking Your Data

To get accurate performance metrics for your specific data:

```bash
# Basic benchmark
time zmin your-file.json > /dev/null

# Detailed benchmark with memory profiling
zmin --benchmark --memory-profile your-file.json

# Compare different modes
for mode in eco sport turbo; do
    echo "Mode: $mode"
    time zmin --mode=$mode your-file.json > /dev/null
done
```

## When to Use Each Mode

### Eco Mode
- CI/CD pipelines with resource limits
- Battery-powered devices
- Small to medium files
- When consistency matters more than speed

### Sport Mode
- General-purpose processing
- Good balance for most use cases
- Default recommendation

### Turbo Mode
- Large file processing
- Batch processing jobs
- When speed is critical
- Dedicated processing servers

For more details, see our [Performance Metrics](/docs/performance-metrics/) page.