# zmin Development Tools Troubleshooting Guide

This guide helps resolve common issues with zmin development tools.

## Quick Diagnosis

### Check Tool Status

```bash
# Verify tools are installed and accessible
which debugger dev-server profiler config-manager plugin-registry hot-reloading

# Check tool versions
debugger --version 2>/dev/null || echo "debugger not available"
dev-server --help | head -1 2>/dev/null || echo "dev-server not available"
profiler --help | head -1 2>/dev/null || echo "profiler not available"
```

### System Requirements Check

```bash
# Check system resources
echo "CPU cores: $(nproc)"
echo "Memory: $(free -h | awk 'NR==2{print $2}')"
echo "Disk space: $(df -h . | awk 'NR==2{print $4}')"

# Check Zig version
zig version
```

## Common Issues

### 1. Installation Problems

#### Problem: Tools not found after installation

```bash
# Symptoms
debugger: command not found
dev-server: command not found
```

**Solution:**

```bash
# Check if tools are built
ls -la zig-out/bin/

# If missing, rebuild tools
zig build tools

# Check PATH includes tool directory
echo $PATH | grep -q "$(pwd)/zig-out/bin" || echo "Add $(pwd)/zig-out/bin to PATH"

# Add to PATH temporarily
export PATH="$(pwd)/zig-out/bin:$PATH"

# Add to shell profile permanently
echo 'export PATH="$(pwd)/zig-out/bin:$PATH"' >> ~/.bashrc
```

#### Problem: Permission denied errors

```bash
# Symptoms
./zig-out/bin/debugger: Permission denied
```

**Solution:**

```bash
# Make tools executable
chmod +x zig-out/bin/*

# Check file permissions
ls -la zig-out/bin/
```

#### Problem: Build failures

```bash
# Symptoms
error: FileNotFound
error: OutOfMemory during compilation
```

**Solution:**

```bash
# Clean build artifacts
zig build clean
rm -rf zig-cache zig-out

# Rebuild with verbose output
zig build tools --verbose

# Check disk space
df -h .

# Try minimal build if memory limited
zig build tools -Doptimize=Debug
```

### 2. Dev Server Issues

#### Problem: Server won't start

```bash
# Symptoms
dev-server: Address already in use
dev-server: Bind failed
dev-server: Permission denied
```

**Solution:**

```bash
# Check if port is in use
netstat -tlnp | grep :8080
lsof -i :8080

# Kill existing process
pkill -f dev-server

# Try different port
dev-server 8081

# Check firewall (Linux)
sudo ufw status
sudo ufw allow 8080

# Check SELinux (if applicable)
setenforce 0  # Temporarily disable
```

#### Problem: API requests fail

```bash
# Symptoms
curl: (7) Failed to connect
curl: (52) Empty reply from server
HTTP 500 Internal Server Error
```

**Solution:**

```bash
# Check server status
curl -f http://localhost:8080/api/stats

# Check server logs
dev-server 8080 --verbose

# Test with simple request
curl -X POST http://localhost:8080/api/minify \
  -H "Content-Type: application/json" \
  -d '{"input": "{\"test\": true}", "mode": "sport"}'

# Check request format
echo '{"input": "{\"valid\": \"json\"}", "mode": "sport"}' | jq .
```

#### Problem: CORS errors in browser

```bash
# Symptoms
Access to fetch at 'http://localhost:8080' from origin 'http://localhost:3000' has been blocked by CORS policy
```

**Solution:**

```bash
# Server automatically handles CORS with Access-Control-Allow-Origin: *
# If still having issues, check browser developer tools
# Verify server is setting CORS headers:
curl -I http://localhost:8080/api/stats | grep -i "access-control"
```

### 3. Debugger Issues

#### Problem: No performance data

```bash
# Symptoms
debugger: No timing information available
debugger: Benchmark failed
```

**Solution:**

```bash
# Check input file exists and is valid JSON
test -f input.json && echo "File exists" || echo "File missing"
cat input.json | jq . >/dev/null && echo "Valid JSON" || echo "Invalid JSON"

# Try with simple input
echo '{"test": "data"}' > simple.json
debugger -i simple.json --benchmark 5

# Reduce benchmark iterations
debugger -i input.json --benchmark 1

# Check system load
uptime
top -bn1 | head -5
```

#### Problem: Memory tracking errors

```bash
# Symptoms
debugger: Memory tracking failed
debugger: Out of memory
```

**Solution:**

```bash
# Disable memory tracking temporarily
debugger -i input.json --no-memory-tracking

# Check available memory
free -h
cat /proc/meminfo | head -5

# Use smaller input file
head -100 large.json > small.json
debugger -i small.json
```

#### Problem: Profiling crashes

```bash
# Symptoms
Segmentation fault
debugger: Profiling error
```

**Solution:**

```bash
# Disable profiling features
debugger -i input.json --no-profiling --no-memory-tracking

# Run with minimal options
debugger -i input.json --benchmark 1

# Check for stack overflow
ulimit -s unlimited

# Try debug build
zig build tools -Doptimize=Debug
```

### 4. Profiler Issues

#### Problem: Profiling hangs or takes too long

```bash
# Symptoms
profiler: Process appears frozen
profiler: Very slow performance
```

**Solution:**

```bash
# Reduce iterations
profiler --input data.json --modes sport --iterations 5

# Use single mode
profiler --input data.json --modes eco

# Check system resources
htop  # or top
iotop  # check disk I/O

# Try with smaller file
head -10 data.json > small.json
profiler --input small.json
```

#### Problem: Output directory errors

```bash
# Symptoms
profiler: Cannot create output directory
profiler: Permission denied writing results
```

**Solution:**

```bash
# Check directory permissions
ls -ld ./profiles/
mkdir -p ./profiles
chmod 755 ./profiles

# Use different output directory
profiler --input data.json --output-dir /tmp/profiles

# Check disk space
df -h .
```

### 5. Configuration Issues

#### Problem: Config file not found

```bash
# Symptoms
config-manager: Configuration file not found
config-manager: Cannot load config
```

**Solution:**

```bash
# Check config file location
ls -la zmin.config.json
ls -la ~/.config/zmin/config.json
ls -la /etc/zmin/config.json

# Create default config
config-manager --save-config zmin.config.json

# Specify config file explicitly
config-manager --load-config /path/to/config.json
```

#### Problem: Invalid configuration

```bash
# Symptoms
config-manager: Invalid JSON
config-manager: Configuration validation failed
```

**Solution:**

```bash
# Validate JSON syntax
cat zmin.config.json | jq .

# Check for common JSON errors
# - Missing commas
# - Trailing commas
# - Unquoted keys
# - Invalid escape sequences

# Use config validation
config-manager --validate-config zmin.config.json

# Reset to defaults
mv zmin.config.json zmin.config.json.backup
config-manager --save-config zmin.config.json
```

### 6. Plugin Issues

#### Problem: No plugins found

```bash
# Symptoms
plugin-registry: No plugins discovered
plugin-registry: Plugin directory empty
```

**Solution:**

```bash
# Check plugin search paths
plugin-registry list

# Create plugin directory
mkdir -p ~/.zmin/plugins
mkdir -p ./plugins

# Check plugin paths in config
config-manager --get-value plugin_registry.search_paths

# Verify plugin files exist
ls -la ~/.zmin/plugins/
ls -la ./plugins/
```

#### Problem: Plugin loading fails

```bash
# Symptoms
plugin-registry: Failed to load plugin
plugin-registry: Plugin interface mismatch
```

**Solution:**

```bash
# Check plugin file format
file ~/.zmin/plugins/*.so
file ~/.zmin/plugins/*.dll

# Verify plugin is compatible
plugin-registry info 0

# Check plugin dependencies
ldd ~/.zmin/plugins/plugin.so  # Linux
otool -L ~/.zmin/plugins/plugin.dylib  # macOS

# Rebuild plugin if source available
cd plugin-source/
zig build
cp zig-out/lib/* ~/.zmin/plugins/
```

### 7. Hot Reloading Issues

#### Problem: File changes not detected

```bash
# Symptoms
hot-reloading: No file change events
hot-reloading: Files modified but no action triggered
```

**Solution:**

```bash
# Check file permissions
ls -la watched-directory/

# Test file system events
inotifywait -m . -e modify  # Linux
fswatch .  # macOS

# Verify watch patterns
hot-reloading --watch "*.json" --debug

# Reduce debounce time
hot-reloading --watch "*.json" --debounce 100

# Check for file system limits
cat /proc/sys/fs/inotify/max_user_watches  # Linux
```

#### Problem: Command execution fails

```bash
# Symptoms
hot-reloading: Command failed
hot-reloading: Execution error
```

**Solution:**

```bash
# Test command manually
zmin test.json

# Check command path
which zmin
echo $PATH

# Use full path in command
hot-reloading --watch "*.json" --exec "/full/path/to/zmin {file}"

# Check file placeholders
hot-reloading --watch "*.json" --exec "echo Processing: {file}"
```

## Performance Issues

### Memory Problems

```bash
# Check memory usage
ps aux | grep -E "(debugger|dev-server|profiler)"
free -h

# Reduce memory usage
debugger --no-memory-tracking --no-profiling
profiler --iterations 10
```

### CPU Problems

```bash
# Check CPU usage
top -p $(pgrep -d, -f "debugger|dev-server|profiler")

# Reduce CPU usage
debugger --benchmark 5
profiler --modes sport  # Instead of all modes
```

### Disk I/O Problems

```bash
# Check disk usage
iotop
df -h .

# Reduce disk I/O
profiler --no-save-raw-data
hot-reloading --debounce 2000  # Longer debounce
```

## Debugging Steps

### 1. Enable Debug Mode

```bash
# Enable debug output for tools
export ZMIN_DEBUG=1
export ZMIN_LOG_LEVEL=debug

# Run with verbose flags
debugger -i data.json --verbose
dev-server 8080 --verbose
profiler --input data.json --debug
```

### 2. Check System Logs

```bash
# Check system logs
journalctl -f  # Linux systemd
tail -f /var/log/syslog  # Linux
tail -f /var/log/system.log  # macOS

# Check for core dumps
ls -la core.*
dmesg | tail
```

### 3. Use System Debugging Tools

```bash
# Memory debugging with Valgrind (Linux)
valgrind --leak-check=full debugger -i data.json

# System call tracing
strace -e file debugger -i data.json  # Linux
dtruss -f debugger -i data.json  # macOS

# Library dependency check
ldd zig-out/bin/debugger  # Linux
otool -L zig-out/bin/debugger  # macOS
```

## Recovery Procedures

### Reset Configuration

```bash
# Backup current config
cp zmin.config.json zmin.config.json.backup

# Create fresh config
config-manager --save-config zmin.config.json.fresh

# Load minimal config
cat > minimal.config.json << 'EOF'
{
  "global": {
    "log_level": "info"
  },
  "dev_server": {
    "port": 8080
  }
}
EOF

config-manager --load-config minimal.config.json
```

### Clean Rebuild

```bash
# Complete clean rebuild
zig build clean
rm -rf zig-cache zig-out .zig-cache

# Rebuild everything
zig build
zig build tools

# Verify build
ls -la zig-out/bin/
```

### Emergency Debugging

```bash
# Minimal test setup
mkdir -p debug-test
cd debug-test

# Create simple test case
echo '{"test": "data"}' > test.json

# Test each tool individually
../zig-out/bin/debugger -i test.json --benchmark 1
../zig-out/bin/profiler --input test.json --modes sport --iterations 5
../zig-out/bin/dev-server 8081 &
sleep 2 && curl http://localhost:8081/api/stats && pkill -f dev-server
```

## Environment-Specific Issues

### Linux

```bash
# Check glibc version compatibility
ldd --version

# SELinux issues
getenforce
setenforce 0  # Temporary disable

# Systemd service issues
systemctl status zmin-dev-server
journalctl -u zmin-dev-server
```

### macOS

```bash
# Check macOS version compatibility
sw_vers

# Gatekeeper issues
xattr -d com.apple.quarantine zig-out/bin/*

# SIP issues (if tools installed in system directories)
csrutil status
```

### Windows

```bash
# Check Windows version
ver

# Antivirus interference
# Temporarily disable Windows Defender or add exclusions

# UAC issues
# Run as administrator if needed

# Path issues
echo %PATH%
where debugger
```

## Getting Additional Help

### Collect Debug Information

```bash
#!/bin/bash
# collect-debug-info.sh

echo "=== System Information ==="
uname -a
zig version
echo ""

echo "=== Tool Status ==="
ls -la zig-out/bin/ 2>/dev/null || echo "Tools not built"
echo ""

echo "=== Memory and Disk ==="
free -h
df -h .
echo ""

echo "=== Network ==="
netstat -tlnp | grep :8080 || echo "Port 8080 not in use"
echo ""

echo "=== Recent Logs ==="
tail -20 /var/log/syslog 2>/dev/null || echo "No system logs available"
```

### Community Support

- **GitHub Issues**: https://github.com/user/zmin/issues
- **Discussions**: https://github.com/user/zmin/discussions
- **Documentation**: https://github.com/user/zmin/tree/main/docs

### Bug Reports

When reporting issues, include:

1. Operating system and version
2. Zig version (`zig version`)
3. Tool version and build info
4. Complete error messages
5. Steps to reproduce
6. Input files (if applicable)
7. System resource information
8. Output of debug info collection script

## Prevention

### Regular Maintenance

```bash
# Weekly maintenance script
#!/bin/bash

echo "Running weekly zmin maintenance..."

# Update tools
zig build tools --release=fast

# Clean old logs and temporary files
find . -name "*.log" -mtime +7 -delete
find /tmp -name "zmin-*" -mtime +1 -delete 2>/dev/null || true

# Validate configuration
config-manager --validate-config zmin.config.json

# Test critical functionality
echo '{"test": "maintenance"}' | debugger --benchmark 5

echo "Maintenance completed"
```

### Monitoring Script

```bash
#!/bin/bash
# monitor-health.sh

# Check tool health
TOOLS=("debugger" "dev-server" "profiler" "config-manager")

for tool in "${TOOLS[@]}"; do
    if which "$tool" >/dev/null 2>&1; then
        echo "✅ $tool: Available"
    else
        echo "❌ $tool: Missing"
    fi
done

# Check system resources
MEMORY_USAGE=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
DISK_USAGE=$(df . | awk 'NR==2{printf "%.1f", $5}' | sed 's/%//')

echo "Memory usage: ${MEMORY_USAGE}%"
echo "Disk usage: ${DISK_USAGE}%"

if (( $(echo "$MEMORY_USAGE > 90" | bc -l) )); then
    echo "⚠️  High memory usage"
fi

if (( $(echo "$DISK_USAGE > 90" | bc -l) )); then
    echo "⚠️  High disk usage" 
fi
```