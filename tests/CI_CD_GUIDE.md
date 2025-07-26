# Zmin CI/CD Pipeline Guide

## Overview

Zmin features a comprehensive CI/CD pipeline that automatically builds, tests, benchmarks, and generates performance badges. This guide covers the setup, usage, and customization of the pipeline.

## Pipeline Components

### 1. GitHub Actions Workflow (`.github/workflows/ci.yml`)

The main CI/CD pipeline includes:

- **Multi-platform builds** (Linux, macOS, Windows)
- **Multi-Zig version testing** (0.11.0, 0.12.0)
- **Performance benchmarking** with automatic metric extraction
- **Security analysis** with memory safety checks
- **Integration testing** across all components
- **Automatic badge generation** and README updates
- **Release artifact generation** for all platforms

### 2. Performance Monitoring Tools

#### `tools/performance_monitor.zig`

Parses benchmark output and generates structured performance data in JSON format for CI/CD consumption.

**Usage:**

```bash
zig build tools:performance-monitor
./zig-out/bin/performance-monitor benchmark_output.txt
```

**Output:**

```json
{
  "performance": {
    "throughput_gbps": 5.72,
    "memory_mb": 0.064,
    "simd_efficiency": 6400.0,
    "cache_hit_ratio": 100.0,
    "thread_count": 24,
    "cpu_features": "AVX-512,AVX2,SSE2",
    "test_duration_ms": 1234,
    "input_size_mb": 10.0
  },
  "badges": {
    "performance": "https://img.shields.io/badge/Performance-5.72%20GB%2Fs-brightgreen?style=for-the-badge&logo=zig",
    "memory": "https://img.shields.io/badge/Memory-O(1)-blue?style=for-the-badge&logo=memory",
    "simd": "https://img.shields.io/badge/SIMD-6400%25-orange?style=for-the-badge&logo=cpu",
    "build": "https://img.shields.io/badge/Build-Passing-brightgreen?style=for-the-badge&logo=github-actions",
    "zig": "https://img.shields.io/badge/Zig-0.12.0-purple?style=for-the-badge&logo=zig"
  }
}
```

#### `tools/generate_badges.zig`

Downloads and generates performance badges locally.

**Usage:**

```bash
zig build tools:badges
./zig-out/bin/badge-generator --throughput=5.72 --simd=6400 --zig=0.12.0
```

**Generated Badges:**

- `badges/performance.svg` - Throughput performance
- `badges/memory.svg` - Memory efficiency
- `badges/simd.svg` - SIMD optimization
- `badges/build.svg` - Build status
- `badges/zig.svg` - Zig version
- `badges/license.svg` - License information
- `badges/platforms.svg` - Platform support

### 3. Local Testing Script

#### `scripts/test-ci.sh`

Comprehensive local testing script that simulates the entire CI/CD pipeline.

**Usage:**

```bash
./scripts/test-ci.sh
```

**What it tests:**

- Zig installation verification
- Project building
- Test suite execution
- Performance benchmarking
- Badge generation
- Security analysis
- Performance regression testing
- Complete CI pipeline execution
- Artifact verification

## Workflow Triggers

### Automatic Triggers

1. **Push to main/develop branches**
   - Runs full test suite
   - Executes performance benchmarks
   - Updates performance badges
   - Generates release artifacts

2. **Pull Requests**
   - Runs tests on multiple platforms
   - Validates performance metrics
   - Ensures no regressions

3. **Release Tags**
   - Creates GitHub releases
   - Uploads platform-specific artifacts
   - Generates release notes with performance data

### Manual Triggers

Use GitHub Actions UI or API to manually trigger workflows:

```bash
# Trigger via GitHub CLI
gh workflow run ci.yml
```

## Performance Metrics Tracking

### Key Metrics

The pipeline tracks performance metrics as defined in [PERFORMANCE_MODES.md](../docs/PERFORMANCE_MODES.md). Current targets:

- **Throughput**: ≥ 90 MB/s (single-threaded)
- **Memory**: O(1) constant (64KB buffer)
- **Test Coverage**: > 90%

### Regression Detection

The pipeline includes automatic regression detection:

```yaml
# Performance regression test
- name: Performance regression test
  run: |
    THROUGHPUT=$(zig build test:ultimate 2>&1 | grep -oP '(\d+\.\d+)\s*GB/s' | head -1 | grep -oP '\d+\.\d+' || echo "0.0")
    if (( $(echo "$THROUGHPUT < 4.0" | bc -l) )); then
      echo "Performance regression detected: $THROUGHPUT GB/s < 4.0 GB/s"
      exit 1
    fi
```

## Badge System

### Dynamic Badges

Performance badges are automatically updated with each successful build:

- **Performance Badge**: Shows current throughput in GB/s
- **Memory Badge**: Shows O(1) memory efficiency
- **SIMD Badge**: Shows SIMD optimization percentage
- **Build Badge**: Shows current build status
- **Zig Badge**: Shows Zig version compatibility
- **License Badge**: Shows MIT license
- **Platforms Badge**: Shows supported platforms

### Badge URLs

Badges are generated using shields.io and include:

- Performance metrics
- Build status
- Platform support
- Language version
- License information

## Customization

### Adding New Metrics

1. **Update performance monitor:**

   ```zig
   // In tools/performance_monitor.zig
   const PerformanceData = struct {
       // Add new field
       new_metric: f64 = 0.0,
   };
   ```

2. **Update badge generator:**

   ```zig
   // In tools/generate_badges.zig
   try generateBadge(
       "badges/new_metric.svg",
       "New Metric",
       "value",
       "color",
       "logo"
   );
   ```

3. **Update CI workflow:**

   ```yaml
   # In .github/workflows/ci.yml
   - name: Extract new metric
     run: |
       NEW_METRIC=$(echo "$OUTPUT" | grep -oP 'New Metric:\s*(\d+\.\d+)' | grep -oP '\d+\.\d+' || echo "0.0")
       echo "new_metric=$NEW_METRIC" >> $GITHUB_OUTPUT
   ```

### Platform Support

To add new platforms:

1. **Update workflow matrix:**

   ```yaml
   strategy:
     matrix:
       os: [ubuntu-latest, macos-latest, windows-latest, new-platform]
   ```

2. **Add platform-specific build logic:**

   ```yaml
   - name: Platform-specific build
     run: |
       if [[ "$RUNNER_OS" == "NewPlatform" ]]; then
         # Platform-specific commands
       fi
   ```

## Troubleshooting

### Common Issues

1. **Performance regression detected**
   - Check recent code changes
   - Verify system resources
   - Run local benchmarks

2. **Build failures on specific platforms**
   - Check platform-specific dependencies
   - Verify Zig version compatibility
   - Review platform-specific code paths

3. **Badge generation failures**
   - Check internet connectivity
   - Verify shields.io service status
   - Review badge URL encoding

### Debug Commands

```bash
# Run tests locally
zig build test
zig build benchmark

# Verify CI locally
./scripts/test-ci.sh
```

## Best Practices

### For Developers

1. **Always run local CI tests before pushing:**

   ```bash
   ./scripts/test-ci.sh
   ```

2. **Monitor performance regressions:**

   ```bash
   zig build test:ultimate
   ```

3. **Update badges when performance improves:**

   ```bash
   zig build tools:badges --throughput=NEW_VALUE --simd=NEW_VALUE
   ```

### For Maintainers

1. **Review performance trends** in GitHub Actions logs
2. **Monitor badge updates** for accuracy
3. **Validate release artifacts** before publishing
4. **Update documentation** when adding new metrics

## Future Enhancements

### Planned Features

1. **Performance trend analysis** with historical data
2. **Automated performance reports** with detailed breakdowns
3. **Integration with external benchmarking services**
4. **Real-time performance monitoring** dashboard
5. **Automated performance optimization suggestions**

### Contributing to CI/CD

To contribute to the CI/CD pipeline:

1. Fork the repository
2. Make changes to workflow files or tools
3. Test locally with `./scripts/test-ci.sh`
4. Submit a pull request with detailed description
5. Ensure all tests pass and performance is maintained

---

**The CI/CD pipeline ensures Zmin maintains its world-class performance standards while providing transparency and reliability for users and contributors.**
