---
title: "Troubleshooting Guide"
description: "Interactive troubleshooting decision tree for common zmin issues"
weight: 85
---

# Troubleshooting Guide

Use this interactive decision tree to quickly diagnose and resolve common zmin issues.

{{< troubleshooting-tree >}}

## Quick Troubleshooting Checklist

Before using the decision tree, try these quick checks:

### ✅ Basic Checks

1. **Is zmin installed?**
   ```bash
   zmin --version
   ```

2. **Is your JSON valid?**
   ```bash
   zmin --validate-only input.json
   ```

3. **Do you have sufficient permissions?**
   ```bash
   ls -la input.json
   ```

4. **Is there enough disk space?**
   ```bash
   df -h .
   ```

### 🔍 Common Issues

#### Installation Issues

<details>
<summary>zmin: command not found</summary>

**Solution:**
1. Ensure zmin is installed: `brew install zmin` or build from source
2. Check if it's in your PATH: `echo $PATH`
3. Add to PATH if needed: `export PATH=$PATH:/path/to/zmin`
</details>

<details>
<summary>Permission denied when installing</summary>

**Solution:**
1. Use a package manager: `brew install zmin`
2. Or install to user directory: `zig build --prefix ~/.local`
3. Add `~/.local/bin` to your PATH
</details>

#### Performance Issues

<details>
<summary>Processing is slower than expected</summary>

**Solutions:**
1. Use appropriate mode:
   - Small files: `zmin -m eco`
   - Large files: `zmin -m turbo`
2. Enable GPU if available: `zmin --gpu`
3. Check system resources: `top` or `htop`
4. Process files in parallel for multiple files
</details>

<details>
<summary>Out of memory errors</summary>

**Solutions:**
1. Use streaming mode: `zmin --streaming`
2. Reduce buffer size: `zmin --buffer-size=10MB`
3. Process in chunks:
   ```bash
   split -b 100M large.json chunk_
   for chunk in chunk_*; do
       zmin "$chunk"
   done
   cat chunk_*.min > result.json
   ```
</details>

#### Output Issues

<details>
<summary>Output file is empty</summary>

**Possible causes:**
1. Input file is empty
2. Write permissions issue
3. Disk full

**Debug:**
```bash
# Check input file
cat input.json | head

# Check permissions
ls -la output-directory/

# Check disk space
df -h .
```
</details>

<details>
<summary>Output is not minified</summary>

**Check:**
1. Correct mode is used (not validation-only)
2. Input is already minified
3. Use verbose output to see what's happening:
   ```bash
   zmin --verbose input.json
   ```
</details>

### 🛠 Advanced Troubleshooting

#### Debug Mode

Enable detailed logging to diagnose complex issues:

```bash
# Maximum verbosity
zmin --log-level=trace input.json 2> debug.log

# With timing information
zmin --profile --benchmark input.json

# Memory debugging
zmin --memory-profile input.json
```

#### Environment Variables

Set these for additional debugging:

```bash
# Enable debug assertions
export ZMIN_DEBUG=1

# Set custom memory limit
export ZMIN_MEMORY_LIMIT=2GB

# Force specific mode
export ZMIN_DEFAULT_MODE=turbo
```

#### Building from Source

If you're having issues with the binary:

```bash
# Clone repository
git clone https://github.com/hydepwns/zmin
cd zmin

# Build with debug info
zig build -Drelease-safe

# Run tests
zig build test

# Build with specific features
zig build -Dgpu=false -Dsimd=false
```

### 📊 Performance Profiling

For performance issues, gather detailed metrics:

```bash
# CPU profiling
perf record -g zmin large.json
perf report

# Memory profiling
valgrind --tool=massif zmin input.json
ms_print massif.out.*

# Time breakdown
time -v zmin input.json
```

### 🆘 Getting Help

If you're still having issues:

1. **Search existing issues**: [GitHub Issues](https://github.com/hydepwns/zmin/issues)

2. **Create minimal example**:
   ```bash
   # Create test case
   echo '{"test": "data"}' > minimal.json
   zmin --verbose minimal.json
   ```

3. **Gather system info**:
   ```bash
   zmin --version
   uname -a
   zig version
   ```

4. **Report issue** with:
   - Error message
   - Steps to reproduce
   - System information
   - Minimal JSON example

### 💡 Pro Tips

1. **Benchmark before optimizing**: Always measure first
2. **Use appropriate mode**: Don't use Turbo for tiny files
3. **Batch operations**: Process multiple files together
4. **Monitor resources**: Watch CPU and memory usage
5. **Keep zmin updated**: Latest version has bug fixes

## Interactive Troubleshooting

Use the decision tree above to navigate through common issues interactively. Click on your symptoms to reveal specific solutions and next steps.