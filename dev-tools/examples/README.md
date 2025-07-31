# zmin Development Tools Examples

This directory contains comprehensive usage examples for all zmin development tools.

## Available Tools

| Tool | Description | Examples File |
|------|-------------|---------------|
| **debugger** | Performance analysis & debugging | [debugger-examples.md](debugger-examples.md) |
| **dev-server** | Development server with REST API | [dev-server-examples.md](dev-server-examples.md) |
| **profiler** | Performance profiling & benchmarking | [profiler-examples.md](profiler-examples.md) |
| **config-manager** | Configuration management | [config-manager-examples.md](config-manager-examples.md) |
| **plugin-registry** | Plugin discovery & management | [plugin-registry-examples.md](plugin-registry-examples.md) |
| **hot-reloading** | File watching & auto-reload | [hot-reloading-examples.md](hot-reloading-examples.md) |

## Quick Start Examples

### Basic Development Workflow

```bash
# 1. Start development server
dev-server 8080 &

# 2. Set up file watching
hot-reloading --watch "*.json" --exec "zmin {file}" &

# 3. Analyze performance
echo '{"users": [{"id": 1, "name": "John"}]}' > test.json
debugger -i test.json --benchmark 50

# 4. Clean up
pkill -f dev-server
pkill -f hot-reloading
```

### Performance Analysis Pipeline

```bash
# Generate test data
echo '{"data": [' > large.json
for i in {1..1000}; do
  echo "{\"id\": $i, \"value\": \"item$i\"}," >> large.json
done
echo '{}]}' >> large.json

# Comprehensive analysis
profiler --input large.json --modes eco,sport,turbo
debugger -i large.json --benchmark 100 --verbose
```

### Plugin Development

```bash
# Discover available plugins
plugin-registry discover

# Test all plugins
plugin-registry test

# Benchmark plugin performance
plugin-registry benchmark
```

## Common Workflows

### 1. JSON Processing Development

```bash
#!/bin/bash
# json-dev-workflow.sh

echo "🚀 Starting JSON processing development workflow"

# Start development server
echo "Starting dev server..."
dev-server 3000 &
SERVER_PID=$!

# Set up configuration
echo "Configuring tools..."
config-manager --set-value dev_server.port 3000
config-manager --set-value debugger.benchmark_iterations 25

# Start file watcher for auto-processing
echo "Starting file watcher..."
hot-reloading --watch "input/*.json" \
  --exec "zmin {file} --mode sport --output processed/{filename}" &
WATCHER_PID=$!

echo "✅ Development environment ready!"
echo "   - Dev server: http://localhost:3000"
echo "   - Drop JSON files in input/ directory"
echo "   - Processed files will appear in processed/"

# Cleanup on exit
trap "kill $SERVER_PID $WATCHER_PID 2>/dev/null" EXIT
wait
```

### 2. Performance Testing Suite

```bash
#!/bin/bash
# performance-test-suite.sh

echo "🏁 Running comprehensive performance test suite"

TEST_FILES=(
  "tests/fixtures/small.json"
  "tests/fixtures/medium.json"
  "tests/fixtures/large.json"
)

for file in "${TEST_FILES[@]}"; do
  echo "Testing $(basename "$file")..."
  
  # Profile all modes
  profiler --input "$file" --modes eco,sport,turbo
  
  # Detailed analysis
  debugger -i "$file" --benchmark 50
  
  echo "✅ Completed $(basename "$file")"
done

echo "🎯 Performance testing completed!"
```

### 3. Production Monitoring Setup

```bash
#!/bin/bash
# production-monitoring.sh

echo "📊 Setting up production monitoring"

# Configure for production
config-manager --load-config configs/production.json
config-manager --set-value global.log_level warn

# Start monitoring services
dev-server 8080 &
SERVER_PID=$!

# Monitor configuration changes
hot-reloading --watch "configs/*.json" \
  --exec "config-manager --validate-config {file} && systemctl reload zmin" &
CONFIG_WATCHER_PID=$!

# Monitor data processing
hot-reloading --watch "data/*.json" \
  --debounce 2000 \
  --exec "profiler --input {file} --modes turbo --output-dir /var/log/zmin/profiles" &
DATA_WATCHER_PID=$!

echo "✅ Production monitoring active"
echo "   - API server: http://localhost:8080"
echo "   - Config monitoring: enabled"
echo "   - Data processing: enabled"

trap "kill $SERVER_PID $CONFIG_WATCHER_PID $DATA_WATCHER_PID 2>/dev/null" EXIT
wait
```

## Integration Examples

### Docker Compose Development Environment

```yaml
# docker-compose.dev.yml
version: '3.8'

services:
  zmin-dev:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "8080:8080"
    volumes:
      - .:/app
      - ./data:/app/data
    environment:
      - ZMIN_CONFIG=/app/configs/development.json
    command: >
      sh -c "
        config-manager --load-config /app/configs/development.json &&
        dev-server 8080 &
        hot-reloading --watch '/app/src/**/*.zig' --exec 'zig build' &
        wait
      "

  zmin-profiler:
    build:
      context: .
      dockerfile: Dockerfile.dev
    volumes:
      - ./data:/app/data
      - ./profiles:/app/profiles
    command: >
      hot-reloading --watch '/app/data/*.json' 
        --exec 'profiler --input {file} --output-dir /app/profiles'
```

### GitHub Actions Integration

```yaml
# .github/workflows/dev-tools-test.yml
name: Dev Tools Integration Test

on: [push, pull_request]

jobs:
  test-dev-tools:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Zig
      uses: goto-bus-stop/setup-zig@v2
      with:
        version: 0.13.0
    
    - name: Build dev tools
      run: zig build tools
    
    - name: Test complete workflow
      run: |
        # Start dev server
        ./zig-out/bin/dev-server 8080 &
        SERVER_PID=$!
        sleep 2
        
        # Test API
        echo '{"test": "data"}' > test.json
        curl -X POST http://localhost:8080/api/minify \
          -H "Content-Type: application/json" \
          -d '{"input": "{\"test\": \"data\"}", "mode": "sport"}'
        
        # Test other tools
        ./zig-out/bin/debugger -i test.json --benchmark 10
        ./zig-out/bin/profiler --input test.json --modes eco,sport,turbo
        
        # Cleanup
        kill $SERVER_PID
        
        echo "✅ All dev tools tested successfully"
```

## Configuration Templates

### Development Configuration

```json
{
  "global": {
    "log_level": "debug",
    "enable_telemetry": false
  },
  "dev_server": {
    "port": 3000,
    "enable_debugging": true,
    "log_requests": true
  },
  "debugger": {
    "debug_level": "verbose",
    "benchmark_iterations": 25
  },
  "profiler": {
    "default_iterations": 10,
    "save_raw_data": true
  },
  "hot_reloading": {
    "debounce_ms": 300,
    "watch_patterns": ["src/**/*.zig", "data/*.json"]
  }
}
```

### Production Configuration

```json
{
  "global": {
    "log_level": "warn",
    "enable_telemetry": true
  },
  "dev_server": {
    "port": 8080,
    "host": "0.0.0.0",
    "enable_debugging": false
  },
  "debugger": {
    "debug_level": "basic",
    "benchmark_iterations": 100
  },
  "profiler": {
    "default_iterations": 50,
    "save_raw_data": false
  },
  "hot_reloading": {
    "debounce_ms": 2000,
    "watch_patterns": ["configs/*.json"]
  }
}
```

## Best Practices

### 1. Tool Selection

- **debugger**: Use for detailed performance analysis and troubleshooting
- **dev-server**: Use for API-based integration and web interfaces
- **profiler**: Use for comprehensive benchmarking and comparison
- **config-manager**: Use for centralized configuration management
- **plugin-registry**: Use for extending functionality with custom plugins
- **hot-reloading**: Use for development automation and file monitoring

### 2. Performance Considerations

- Use appropriate benchmark iterations (10-50 for development, 100+ for production)
- Configure debounce times to prevent excessive rebuilds
- Monitor system resources when running multiple tools
- Use specific file patterns to reduce monitoring overhead

### 3. Development Workflow

1. Start with basic tools (debugger, dev-server)
2. Add automation (hot-reloading) as needed
3. Implement comprehensive monitoring (profiler) for critical paths
4. Use configuration management for environment consistency
5. Extend with plugins for custom requirements

### 4. Production Deployment

- Use minimal tool configurations for production
- Enable telemetry and monitoring
- Implement health checks and auto-restart mechanisms
- Secure API endpoints and configuration files
- Monitor performance regularly with profiler

## Getting Help

Each tool provides detailed help information:

```bash
debugger --help
dev-server --help
profiler --help
config-manager --help
plugin-registry --help
hot-reloading --help
```

For more detailed information, see the individual example files for each tool.