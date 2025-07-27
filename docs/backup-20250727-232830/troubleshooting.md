# Troubleshooting Guide

This guide helps you diagnose and fix common issues with zmin.

## Quick Diagnostics

### Check zmin Status

```bash
# Verify installation
zmin --version

# Test basic functionality
echo '{"test": true}' | zmin

# Run built-in diagnostics
zmin --self-test
```

## Common Issues

### 1. Installation Problems

#### Issue: "zmin: command not found"

**Cause**: zmin is not in your PATH or not installed.

**Solutions**:
```bash
# If built from source, add to PATH
export PATH=$PATH:/path/to/zmin/zig-out/bin

# Or install system-wide
sudo cp zig-out/bin/zmin /usr/local/bin/

# Verify installation
which zmin
```

#### Issue: "Permission denied" when running zmin

**Cause**: Binary doesn't have execute permissions.

**Solution**:
```bash
chmod +x /path/to/zmin
```

#### Issue: Build fails with "zig: command not found"

**Cause**: Zig compiler not installed or not in PATH.

**Solutions**:
```bash
# Install Zig
# Linux/macOS
wget https://ziglang.org/download/0.14.1/zig-linux-x86_64-0.14.1.tar.xz
tar -xf zig-linux-x86_64-0.14.1.tar.xz
export PATH=$PATH:$(pwd)/zig-linux-x86_64-0.14.1

# Or via package manager
# macOS
brew install zig

# Verify Zig installation
zig version
```

### 2. Performance Issues

#### Issue: Slower than expected performance

**Diagnosis Steps**:
```bash
# Check current mode
zmin --verbose input.json output.json

# Try different modes
zmin --mode eco input.json output.json     # ~312 MB/s
zmin --mode sport input.json output.json   # ~555 MB/s  
zmin --mode turbo input.json output.json   # ~1.1 GB/s

# Check system resources
top -p $(pgrep zmin)
iostat -x 1
```

**Common Causes & Solutions**:

1. **Wrong mode for file size**:
   - Files < 1MB: Use ECO or SPORT mode
   - Files > 100MB: Use TURBO mode
   ```bash
   # Auto-select mode based on file size
   file_size=$(stat -c%s input.json)
   if [ $file_size -gt 104857600 ]; then
       zmin --mode turbo input.json output.json
   else
       zmin --mode sport input.json output.json
   fi
   ```

2. **I/O bottleneck**:
   ```bash
   # Check disk I/O
   iotop -o
   
   # Use faster storage
   cp input.json /tmp/input.json
   zmin /tmp/input.json /tmp/output.json
   cp /tmp/output.json output.json
   ```

3. **CPU throttling**:
   ```bash
   # Check CPU frequency
   cat /proc/cpuinfo | grep "cpu MHz"
   
   # Set performance governor (Linux)
   sudo cpupower frequency-set -g performance
   ```

#### Issue: High memory usage

**Diagnosis**:
```bash
# Monitor memory usage
/usr/bin/time -v zmin input.json output.json

# Check for memory leaks
valgrind --leak-check=full zmin input.json output.json
```

**Solutions**:
```bash
# Use ECO mode for memory-constrained environments
zmin --mode eco input.json output.json

# Process in chunks for very large files
split -n 4 huge-file.json chunk-
for chunk in chunk-*; do
    zmin --mode eco "$chunk" "$chunk.min"
done
cat chunk-*.min > output.json
```

### 3. JSON Processing Errors

#### Issue: "Invalid JSON" error

**Diagnosis**:
```bash
# Validate JSON first
zmin --validate input.json

# Check JSON syntax with verbose errors
jq empty input.json
```

**Common JSON Issues**:
1. **Trailing commas**:
   ```json
   // ❌ Invalid
   {"key": "value",}
   
   // ✅ Valid  
   {"key": "value"}
   ```

2. **Unescaped quotes**:
   ```json
   // ❌ Invalid
   {"message": "She said "hello""}
   
   // ✅ Valid
   {"message": "She said \"hello\""}
   ```

3. **UTF-8 encoding issues**:
   ```bash
   # Check file encoding
   file -i input.json
   
   # Convert to UTF-8
   iconv -f iso-8859-1 -t utf-8 input.json > input_utf8.json
   ```

#### Issue: Output differs from input

**Cause**: zmin removes unnecessary whitespace by design.

**Verification**:
```bash
# Verify JSON equivalence
jq --compact-output . input.json > expected.json
diff expected.json output.json

# Or use JSON comparison tool
python3 -c "
import json
with open('input.json') as f1, open('output.json') as f2:
    data1, data2 = json.load(f1), json.load(f2)
    print('Equal:', data1 == data2)
"
```

### 4. Language Binding Issues

#### Node.js Issues

**Issue**: "Cannot find module 'zmin'"

**Solutions**:
```bash
# Install the correct package
npm install zmin                # Native addon
npm install @zmin/cli          # CLI package

# Check installation
npm list | grep zmin
```

**Issue**: "Node.js version incompatible"

**Solution**:
```bash
# Check Node.js version
node --version

# Upgrade to Node.js 16+ 
nvm install 16
nvm use 16
```

#### Python Issues

**Issue**: "ModuleNotFoundError: No module named 'zmin'"

**Solutions**:
```bash
# Install package
pip install zmin

# Check installation
pip list | grep zmin

# Use virtual environment
python -m venv venv
source venv/bin/activate
pip install zmin
```

**Issue**: "Shared library not found"

**Solution**:
```bash
# Build shared library
cd /path/to/zmin
zig build c-api

# Copy to system location
sudo cp zig-out/lib/libzmin.so /usr/local/lib/
sudo ldconfig
```

#### Go Issues

**Issue**: "Package not found"

**Solutions**:
```bash
# Use correct import path
go get github.com/hydepwns/zmin/go

# Verify module
go mod tidy
```

### 5. File Access Issues

#### Issue: "Permission denied" reading/writing files

**Solutions**:
```bash
# Check file permissions
ls -la input.json output.json

# Fix permissions
chmod 644 input.json
chmod 755 $(dirname output.json)

# Run with appropriate user
sudo -u fileowner zmin input.json output.json
```

#### Issue: "No space left on device"

**Solutions**:
```bash
# Check disk space
df -h

# Use different output location
zmin input.json /tmp/output.json

# Clean up temporary files
rm -rf /tmp/zmin-*
```

## Performance Debugging

### Profiling Tools

#### Built-in Profiling
```bash
# Enable detailed profiling
zmin --profile --verbose input.json output.json

# Sample output:
# ═══════════════════════════════════════
# Profile Report
# ═══════════════════════════════════════
# Parsing:      120ms (13.3%)
# Validation:    80ms (8.9%)
# Minification: 450ms (50.0%)
# Output:       250ms (27.8%)
# ═══════════════════════════════════════
```

#### External Profiling
```bash
# CPU profiling (Linux)
perf record -g zmin input.json output.json
perf report

# Memory profiling
valgrind --tool=massif zmin input.json output.json
ms_print massif.out.*

# System call tracing
strace -c zmin input.json output.json
```

### Performance Checklist

1. **✅ Correct mode for file size**
2. **✅ Adequate system resources**
3. **✅ Fast storage (SSD preferred)**
4. **✅ CPU not throttled**
5. **✅ Sufficient RAM available**
6. **✅ No competing processes**

## Environment-Specific Issues

### Docker/Container Issues

**Issue**: Performance degradation in containers

**Solutions**:
```dockerfile
# Use performance-optimized base image
FROM alpine:latest

# Set CPU affinity
RUN echo 'taskset -c 0-3 zmin "$@"' > /usr/local/bin/zmin-wrapper
RUN chmod +x /usr/local/bin/zmin-wrapper

# Allocate sufficient memory
# docker run -m 2g your-image
```

### macOS Issues

**Issue**: "zmin cannot be opened because it is from an unidentified developer"

**Solutions**:
```bash
# Allow execution
sudo xattr -r -d com.apple.quarantine /path/to/zmin

# Or build from source
git clone https://github.com/hydepwns/zmin
cd zmin && zig build --release=fast
```

### Windows Issues

**Issue**: "The system cannot find the file specified"

**Solutions**:
```cmd
# Add to PATH
set PATH=%PATH%;C:\path\to\zmin

# Or use full path
C:\path\to\zmin\zmin.exe input.json output.json
```

## Getting Help

### Debug Information Collection

When reporting issues, include:

```bash
# System information
zmin --version
zig version
uname -a

# Reproduction case
echo '{"test": true}' | zmin --verbose 2>&1

# Performance data
time zmin --mode turbo --stats large-file.json /dev/null
```

### Support Channels

- **GitHub Issues**: [github.com/hydepwns/zmin/issues](https://github.com/hydepwns/zmin/issues)
- **Documentation**: [zmin.droo.foo](https://zmin.droo.foo)
- **Performance Guide**: [zmin.droo.foo/performance](https://zmin.droo.foo/performance)

### Issue Templates

**Performance Issue**:
```
**System**: [OS, CPU, RAM]
**zmin version**: [output of zmin --version]
**File size**: [input file size]
**Expected performance**: [MB/s]
**Actual performance**: [MB/s]
**Command used**: [exact command]
**Profiling output**: [zmin --profile output]
```

**Error Report**:
```
**Error message**: [exact error text]
**Input file**: [sample or description]
**Command**: [exact command used]
**Environment**: [OS, architecture]
**Stack trace**: [if available]
```

## Advanced Troubleshooting

### Custom Debugging

```bash
# Enable debug logging
ZMIN_DEBUG=1 zmin input.json output.json

# Use debug build
zig build -Doptimize=Debug
./zig-out/bin/zmin input.json output.json

# Memory debugging
ZMIN_DEBUG_MEMORY=1 zmin input.json output.json
```

### Recovery Procedures

If zmin appears to hang:
```bash
# Send interrupt signal
kill -INT $(pgrep zmin)

# Check for deadlock
gdb -p $(pgrep zmin)
(gdb) thread apply all bt
```

## Prevention

### Best Practices

1. **Always validate large JSON files** before processing
2. **Use appropriate modes** for file sizes
3. **Monitor system resources** during batch operations
4. **Test with sample data** before processing critical files
5. **Keep backups** of important data
6. **Update zmin regularly** for performance improvements

### Automated Health Checks

```bash
#!/bin/bash
# health-check.sh

echo "=== zmin Health Check ==="

# Version check
echo "Version: $(zmin --version)"

# Basic functionality
if echo '{"test": true}' | zmin > /dev/null 2>&1; then
    echo "✅ Basic functionality: OK"
else
    echo "❌ Basic functionality: FAILED"
fi

# Performance test
start_time=$(date +%s%N)
dd if=/dev/zero bs=1M count=10 2>/dev/null | sed 's/\x0/{"x":1}/g' | zmin > /dev/null
end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000 ))
echo "⏱️  Performance test: ${duration}ms"

echo "=== Health Check Complete ==="
```

This troubleshooting guide should help users quickly identify and resolve common issues with zmin.