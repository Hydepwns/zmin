---
title: "Performance Metrics"
description: "Real-time performance metrics and benchmarks for zmin"
weight: 50
---

# Performance Metrics

zmin is engineered for maximum performance. This page displays real-time performance metrics updated daily by our CI/CD pipeline.

{{< performance-dashboard >}}

## Benchmark Methodology

Our performance measurements use:

- **Datasets**: Ranging from tiny (1KB) to xlarge (1GB) JSON files
- **Hardware**: Standardized CI runners for consistent results
- **Metrics**: Throughput (GB/s), memory usage, and processing time
- **Comparison**: Against leading JSON processing libraries

## Performance Modes

zmin offers three performance modes:

{{< level "beginner" >}}
### Eco Mode
- Balanced performance and memory usage
- Suitable for most applications
- ~3 GB/s throughput
{{< /level >}}

{{< level "intermediate" >}}
### Sport Mode
- Optimized for throughput
- Moderate memory usage
- ~4 GB/s throughput
{{< /level >}}

{{< level "advanced" >}}
### Turbo Mode
- Maximum performance
- SIMD optimizations enabled
- GPU acceleration available
- 5+ GB/s throughput
{{< /level >}}

## Understanding the Metrics

### Throughput
Measured in gigabytes per second (GB/s), this represents how much JSON data zmin can process per second.

### Memory Usage
Peak memory consumption during processing. zmin is designed to maintain low memory footprint even with large files.

### Binary Size
The size of the compiled zmin executable, demonstrating our commitment to minimal dependencies and efficient code.

## Performance Tips

1. **Use Turbo Mode** for maximum throughput when processing large files
2. **Enable GPU acceleration** for datasets larger than 100MB
3. **Use streaming mode** for files that don't fit in memory
4. **Batch small files** together for better throughput

## Contributing

Help us improve performance:

- Run benchmarks on your hardware
- Report performance regressions
- Contribute optimizations

See our [Performance Tuning Guide](/docs/development/performance-tuning/) for details.