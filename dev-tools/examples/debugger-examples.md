# Debugger Tool Examples

The debugger tool provides performance analysis, profiling, and debugging capabilities for JSON minification workflows.

## Basic Usage

### Simple Performance Analysis

```bash
# Analyze a JSON file with default settings
debugger -i data.json

# Verbose output for detailed information
debugger -i data.json --verbose

# Trace level for maximum detail
debugger -i data.json --trace
```

### Mode-Specific Analysis

```bash
# Test specific minification mode
debugger -i data.json --mode eco
debugger -i data.json --mode sport  
debugger -i data.json --mode turbo

# Compare all modes performance
debugger -i data.json --benchmark 50
```

## Advanced Examples

### Comprehensive Benchmarking

```bash
# Run 100 iterations for accurate timing
debugger -i large-dataset.json --benchmark 100

# Include memory tracking and profiling
debugger -i data.json --benchmark 50 --verbose

# Test with specific iterations and mode
debugger -i data.json --mode turbo --benchmark 200
```

### Memory Analysis

```bash
# Enable memory tracking for leak detection
debugger -i data.json --benchmark 10

# Check for memory leaks after processing
debugger -i large-file.json --benchmark 5 --verbose

# Memory stress testing with increasing file sizes
debugger --stress-test --stress-size 1024 --stress-multiplier 10
```

### Logging and Output

```bash
# Save detailed logs to file
debugger -i data.json --log debug.log --verbose

# Different log levels
debugger -i data.json --log debug.log --trace
```

### System Information

```bash
# Display system capabilities
debugger --verbose  # Shows CPU features, memory, NUMA info

# Check system performance characteristics
debugger -i small.json --benchmark 10 --verbose
```

## Performance Testing Scenarios

### Small Files (< 1KB)

```bash
# Test eco mode efficiency
debugger -i small.json --mode eco --benchmark 1000

# Compare response times
echo '{"small": "data"}' > tiny.json
debugger -i tiny.json --benchmark 500
```

### Medium Files (1KB - 1MB)

```bash
# Balanced performance testing
debugger -i medium.json --mode sport --benchmark 100

# Profile all modes
debugger -i medium.json --benchmark 50 --verbose
```

### Large Files (> 1MB)

```bash
# Maximum performance mode
debugger -i large.json --mode turbo --benchmark 20

# Memory usage analysis
debugger -i huge.json --benchmark 5 --verbose
```

## Integration Examples

### CI/CD Pipeline Integration

```bash
#!/bin/bash
# performance-test.sh

echo "Running performance regression tests..."

# Test performance thresholds
debugger -i test-data.json --benchmark 50 > perf-results.txt

# Check if performance meets requirements
if grep -q "Average time.*ms" perf-results.txt; then
    echo "✅ Performance test passed"
else
    echo "❌ Performance test failed"
    exit 1
fi
```

### Development Workflow

```bash
#!/bin/bash
# dev-workflow.sh

# Generate test data
echo '{"users": [' > test-data.json
for i in {1..1000}; do
    echo "{\"id\": $i, \"name\": \"User$i\", \"active\": true}," >> test-data.json
done
echo '{"id": 1001, "name": "User1001", "active": true}]}' >> test-data.json

# Run comprehensive analysis
echo "🔍 Running performance analysis..."
debugger -i test-data.json --benchmark 50 --verbose

# Cleanup
rm test-data.json
```

### Automated Testing

```bash
# test-performance.sh
#!/bin/bash

set -e

FILES=(
    "tests/fixtures/small.json"
    "tests/fixtures/medium.json" 
    "tests/fixtures/large.json"
)

for file in "${FILES[@]}"; do
    echo "Testing $file..."
    
    # Run benchmark and capture output
    debugger -i "$file" --benchmark 10 > "results-$(basename "$file").txt"
    
    echo "✅ Completed $file"
done

echo "All performance tests completed!"
```

## Troubleshooting Examples

### Memory Issues

```bash
# Check for memory leaks
debugger -i problematic.json --benchmark 5 --verbose

# Stress test memory usage
debugger --stress-test --stress-size 512 --stress-multiplier 20
```

### Performance Problems

```bash
# Detailed timing analysis
debugger -i slow-file.json --trace --benchmark 10

# System capability check
debugger --verbose  # Check CPU features, memory
```

### Configuration Issues

```bash
# Test with minimal configuration
debugger -i data.json --no-profiling --no-memory-tracking

# Validate tool functionality
debugger --help
```

## Sample Output

```
🔧 zmin Enhanced Debugger started
🖥️  System Information:
  OS: linux
  Architecture: x86_64
  CPU Model: Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz
  CPU Features: SSE SSE2 SSE3 SSSE3 SSE4.1 SSE4.2 AVX AVX2
  Cores: 12
  Threads: 12
  NUMA Nodes: 1
  Total Memory: 32.00 GB
  Available Memory: 24.50 GB

🏁 Starting comprehensive benchmark (50 iterations)
📊 Benchmarking eco mode:
  📈 Results:
    Average time: 1.234ms
    Min time: 0.987ms
    Max time: 2.100ms
    Average memory: 2048 bytes
    Output size: 1456 bytes
    Compression: 78.50%
    Throughput: 312.45 MB/s

📊 Benchmarking sport mode:
  📈 Results:
    Average time: 0.678ms
    Min time: 0.543ms
    Max time: 1.200ms
    Average memory: 4096 bytes
    Output size: 1398 bytes
    Compression: 75.30%
    Throughput: 555.67 MB/s

✅ Enhanced debugger finished
```

## Best Practices

1. **Use appropriate benchmark iterations**: More iterations for more accurate results
2. **Enable verbose mode for debugging**: Get detailed system and performance information
3. **Test with realistic data**: Use production-like JSON files for meaningful results
4. **Monitor memory usage**: Watch for memory leaks in long-running processes
5. **Save logs for analysis**: Use `--log` option to capture detailed information
6. **Combine with other tools**: Use with profiler and dev-server for complete analysis