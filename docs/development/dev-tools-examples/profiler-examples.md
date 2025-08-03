# Profiler Tool Examples

The profiler tool provides comprehensive performance analysis and benchmarking capabilities for JSON minification workflows.

## Basic Usage

### Simple Profiling

```bash
# Profile a JSON file with default settings
profiler --input data.json

# Profile with specific modes
profiler --input data.json --modes eco,sport,turbo

# Profile with custom output directory
profiler --input data.json --output-dir ./performance-reports
```

### Quick Performance Check

```bash
# Fast performance check
echo '{"test": "data"}' | profiler --modes sport

# Profile from stdin
cat large-file.json | profiler --modes turbo --output-dir ./reports
```

## Advanced Examples

### Comprehensive Benchmarking

```bash
# Full benchmark suite with all modes
profiler --input dataset.json \
  --modes eco,sport,turbo \
  --iterations 100 \
  --warmup 10 \
  --output-dir ./benchmarks

# Memory-focused profiling
profiler --input large.json \
  --modes turbo \
  --enable-memory-profiling \
  --memory-sample-rate 1000
```

### Custom Profiling Sessions

```bash
# Extended profiling session
profiler --input data.json \
  --modes eco,sport,turbo \
  --iterations 200 \
  --output-format json \
  --save-raw-data \
  --enable-cpu-profiling

# Minimal overhead profiling
profiler --input sensitive.json \
  --modes sport \
  --no-memory-tracking \
  --no-cpu-profiling \
  --iterations 50
```

### Comparative Analysis

```bash
# Compare different file sizes
FILES=("small.json" "medium.json" "large.json")

for file in "${FILES[@]}"; do
  echo "Profiling $file..."
  profiler --input "$file" \
    --modes eco,sport,turbo \
    --output-dir "./reports/$(basename "$file" .json)" \
    --iterations 50
done
```

## Batch Processing Examples

### Directory Profiling

```bash
#!/bin/bash
# profile-directory.sh

DIRECTORY="./test-data"
OUTPUT_BASE="./profile-results"

echo "Profiling all JSON files in $DIRECTORY..."

for file in "$DIRECTORY"/*.json; do
    filename=$(basename "$file" .json)
    echo "Processing $filename..."
    
    profiler --input "$file" \
      --modes eco,sport,turbo \
      --output-dir "$OUTPUT_BASE/$filename" \
      --iterations 30 \
      --output-format json
      
    echo "✅ Completed $filename"
done

echo "All files profiled!"
```

### Performance Regression Testing

```bash
#!/bin/bash
# regression-test.sh

BASELINE_DIR="./baseline-results"
CURRENT_DIR="./current-results"
TEST_FILES=("test1.json" "test2.json" "test3.json")

echo "Running performance regression tests..."

for file in "${TEST_FILES[@]}"; do
    echo "Testing $file..."
    
    # Profile current version
    profiler --input "tests/fixtures/$file" \
      --modes eco,sport,turbo \
      --output-dir "$CURRENT_DIR/$(basename "$file" .json)" \
      --output-format json \
      --iterations 50
    
    # Compare with baseline (simplified comparison)
    echo "Comparing with baseline..."
    
    # In a real scenario, you'd parse and compare the JSON results
    echo "✅ Regression test completed for $file"
done
```

## Integration Examples

### CI/CD Integration

```bash
#!/bin/bash
# ci-performance-check.sh

set -e

echo "Running CI performance checks..."

# Profile test data
profiler --input tests/performance/benchmark.json \
  --modes eco,sport,turbo \
  --output-dir ./ci-results \
  --output-format json \
  --iterations 20

# Check if performance meets requirements
RESULTS_FILE="./ci-results/profile-results.json"

if [ -f "$RESULTS_FILE" ]; then
    # Extract turbo mode performance (simplified check)
    TURBO_TIME=$(jq -r '.results[] | select(.mode == "turbo") | .average_time_ms' "$RESULTS_FILE")
    
    # Performance threshold: turbo mode should be under 5ms
    if (( $(echo "$TURBO_TIME < 5.0" | bc -l) )); then
        echo "✅ Performance check passed: ${TURBO_TIME}ms"
    else
        echo "❌ Performance check failed: ${TURBO_TIME}ms exceeds 5ms threshold"
        exit 1
    fi
else
    echo "❌ Profile results not found"
    exit 1
fi
```

### Automated Performance Monitoring

```bash
#!/bin/bash
# performance-monitor.sh

MONITOR_DIR="./performance-monitoring"
DATE=$(date +%Y-%m-%d-%H%M%S)
REPORT_DIR="$MONITOR_DIR/$DATE"

echo "Starting performance monitoring session..."

# Create monitoring directory
mkdir -p "$REPORT_DIR"

# Profile standard test cases
TEST_CASES=(
    "tests/small.json:small-file"
    "tests/medium.json:medium-file" 
    "tests/large.json:large-file"
)

for case in "${TEST_CASES[@]}"; do
    IFS=':' read -r file label <<< "$case"
    
    echo "Monitoring $label..."
    
    profiler --input "$file" \
      --modes eco,sport,turbo \
      --output-dir "$REPORT_DIR/$label" \
      --iterations 50 \
      --enable-memory-profiling \
      --enable-cpu-profiling
    
    echo "✅ Completed $label"
done

# Generate summary report
echo "Generating summary report..."
cat > "$REPORT_DIR/summary.md" << EOF
# Performance Monitoring Report - $DATE

## Test Results

$(for case in "${TEST_CASES[@]}"; do
    IFS=':' read -r file label <<< "$case"
    echo "- **$label**: $(basename "$file")"
done)

## Results Location

Results are available in: \`$REPORT_DIR\`

## Next Steps

1. Review individual test results
2. Compare with previous monitoring sessions
3. Identify any performance regressions
EOF

echo "✅ Performance monitoring completed!"
echo "Report available at: $REPORT_DIR/summary.md"
```

## Configuration Examples

### Custom Profiler Configuration

```json
{
  "profiler": {
    "default_modes": ["eco", "sport", "turbo"],
    "default_iterations": 50,
    "warmup_iterations": 5,
    "output_format": "json",
    "enable_memory_profiling": true,
    "enable_cpu_profiling": true,
    "memory_sample_rate": 1000,
    "cpu_sample_rate": 100,
    "output_directory": "./profiles",
    "save_raw_data": false,
    "compression_analysis": true,
    "timing_precision": "nanoseconds"
  }
}
```

### Environment-Specific Settings

```bash
# development.env
export PROFILER_ITERATIONS=10
export PROFILER_MODES="sport"
export PROFILER_OUTPUT_DIR="./dev-profiles"

# production.env  
export PROFILER_ITERATIONS=100
export PROFILER_MODES="eco,sport,turbo"
export PROFILER_OUTPUT_DIR="/var/log/zmin/profiles"

# testing.env
export PROFILER_ITERATIONS=200
export PROFILER_MODES="eco,sport,turbo"
export PROFILER_OUTPUT_DIR="./test-results"
```

## Output Examples

### JSON Output Format

```json
{
  "session_info": {
    "timestamp": "2024-01-29T10:30:00Z",
    "input_file": "test-data.json",
    "input_size": 15420,
    "iterations": 50,
    "warmup_iterations": 5
  },
  "system_info": {
    "cpu": "Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz",
    "cores": 12,
    "memory": "32 GB",
    "os": "linux"
  },
  "results": [
    {
      "mode": "eco",
      "average_time_ms": 2.45,
      "min_time_ms": 2.12,
      "max_time_ms": 3.01,
      "std_deviation": 0.18,
      "throughput_mb_s": 312.5,
      "memory_usage_bytes": 8192,
      "output_size": 12450,
      "compression_ratio": 1.24
    },
    {
      "mode": "sport", 
      "average_time_ms": 1.78,
      "min_time_ms": 1.65,
      "max_time_ms": 2.10,
      "std_deviation": 0.12,
      "throughput_mb_s": 555.2,
      "memory_usage_bytes": 12288,
      "output_size": 12380,
      "compression_ratio": 1.25
    },
    {
      "mode": "turbo",
      "average_time_ms": 1.02,
      "min_time_ms": 0.95,
      "max_time_ms": 1.25,
      "std_deviation": 0.08,
      "throughput_mb_s": 1110.8,
      "memory_usage_bytes": 16384,
      "output_size": 12350,
      "compression_ratio": 1.25
    }
  ],
  "analysis": {
    "fastest_mode": "turbo",
    "most_efficient_mode": "eco",
    "best_compression": "turbo",
    "recommendations": [
      "Use turbo mode for maximum speed",
      "Use eco mode for memory-constrained environments"
    ]
  }
}
```

### Text Report Format

```
================================
Performance Profiling Report
================================

Session Information:
  Date: 2024-01-29 10:30:00 UTC
  Input: test-data.json (15.4 KB)
  Iterations: 50 (5 warmup)

System Information:
  CPU: Intel(R) Core(TM) i7-9750H @ 2.60GHz
  Cores: 12
  Memory: 32 GB
  OS: Linux

Results Summary:
┌─────────┬──────────────┬─────────────┬──────────────┬─────────────────┐
│ Mode    │ Avg Time (ms)│ Throughput  │ Memory (KB)  │ Compression     │
├─────────┼──────────────┼─────────────┼──────────────┼─────────────────┤
│ Eco     │ 2.45         │ 312.5 MB/s  │ 8.0          │ 1.24x           │
│ Sport   │ 1.78         │ 555.2 MB/s  │ 12.0         │ 1.25x           │
│ Turbo   │ 1.02         │ 1110.8 MB/s │ 16.0         │ 1.25x           │
└─────────┴──────────────┴─────────────┴──────────────┴─────────────────┘

Performance Analysis:
  🏆 Fastest: Turbo mode (1.02ms average)
  💾 Most Memory Efficient: Eco mode (8.0 KB)
  🗜️  Best Compression: Turbo mode (1.25x)

Recommendations:
  ✅ Use Turbo mode for maximum throughput
  ✅ Use Eco mode for memory-constrained environments
  ✅ Sport mode provides good balance for general use
```

## Best Practices

### Performance Testing

1. **Use sufficient iterations**: At least 50 iterations for stable results
2. **Include warmup runs**: 5-10 warmup iterations to eliminate cold start effects
3. **Test with realistic data**: Use production-like JSON files
4. **Monitor system resources**: Ensure no other processes interfere
5. **Document test conditions**: Record system state and configuration

### Data Analysis

1. **Compare like with like**: Use same input data across tests
2. **Look at trends**: Monitor performance over time
3. **Consider statistical significance**: Use standard deviation and confidence intervals  
4. **Validate results**: Re-run tests to confirm unusual results
5. **Document findings**: Keep detailed records of performance characteristics

### Automation

1. **Integrate with CI/CD**: Automated performance regression testing
2. **Set performance budgets**: Define acceptable performance thresholds
3. **Monitor production**: Regular performance monitoring in production
4. **Alert on regressions**: Automated alerts when performance degrades
5. **Track improvements**: Document and celebrate performance improvements