# Hot Reloading Examples

The hot-reloading tool provides file watching and automatic reloading capabilities for development workflows.

## Basic Usage

### Simple File Watching

```bash
# Watch JSON files in current directory
hot-reloading --watch "*.json"

# Watch specific file
hot-reloading --watch data.json

# Watch multiple patterns
hot-reloading --watch "*.json,*.zig"
```

### Watch with Actions

```bash
# Execute command when files change
hot-reloading --watch "*.json" --exec "zmin {file}"

# Execute custom script
hot-reloading --watch "src/*.zig" --exec "./build.sh"

# Multiple commands
hot-reloading --watch "*.json" --exec "zmin {file} && echo 'Processed {file}'"
```

## Advanced Examples

### Development Workflow Integration

```bash
#!/bin/bash
# dev-watch.sh

echo "🔄 Starting development file watcher..."

# Watch for source code changes
hot-reloading --watch "src/**/*.zig" \
  --ignore "zig-out/**,zig-cache/**" \
  --debounce 1000 \
  --exec "zig build && echo '✅ Build completed'"
```

### JSON Processing Pipeline

```bash
#!/bin/bash
# json-pipeline.sh

echo "Starting JSON processing pipeline..."

# Watch for JSON files and process them
hot-reloading --watch "input/*.json" \
  --debounce 500 \
  --exec "zmin {file} --mode turbo --output processed/{filename}"
```

### Multi-Stage Processing

```bash
#!/bin/bash
# multi-stage-watch.sh

# Stage 1: Watch source files and build
hot-reloading --watch "src/**/*.zig" \
  --ignore "zig-out/**" \
  --exec "zig build" &

# Stage 2: Watch config files and restart services
hot-reloading --watch "configs/*.json" \
  --exec "pkill -f dev-server && dev-server &" &

# Stage 3: Watch JSON data and process
hot-reloading --watch "data/*.json" \
  --exec "debugger -i {file} --benchmark 10" &

echo "Multi-stage file watching started"
wait
```

## Configuration Examples

### Configuration File

```json
{
  "hot_reloading": {
    "watch_patterns": [
      "src/**/*.zig",
      "data/*.json",
      "configs/*.json"
    ],
    "ignore_patterns": [
      ".git/**",
      "node_modules/**",
      "zig-out/**",
      ".zig-cache/**",
      "*.tmp",
      "*.log"
    ],
    "debounce_ms": 500,
    "recursive": true,
    "follow_symlinks": false,
    "max_files": 10000,
    "actions": {
      "*.zig": "zig build",
      "*.json": "zmin {file} --mode sport",
      "config.json": "systemctl reload zmin-server"
    }
  }
}
```

### Environment-Specific Settings

```bash
# development.env
export HOT_RELOAD_DEBOUNCE=100
export HOT_RELOAD_PATTERNS="src/**/*.zig,data/*.json"
export HOT_RELOAD_COMMAND="zig build && echo 'Development build complete'"

# production.env
export HOT_RELOAD_DEBOUNCE=2000
export HOT_RELOAD_PATTERNS="configs/*.json,data/*.json"
export HOT_RELOAD_COMMAND="systemctl reload zmin-server"
```

## Integration Examples

### Web Development Integration

```bash
#!/bin/bash
# web-dev-server.sh

echo "Starting web development environment..."

# Start dev server
dev-server 3000 &
DEV_SERVER_PID=$!

# Start file watcher for automatic rebuilds
hot-reloading --watch "src/**/*.zig,static/**/*" \
  --ignore "zig-out/**" \
  --debounce 300 \
  --exec "zig build && curl -X POST http://localhost:3000/api/reload" &
HOT_RELOAD_PID=$!

# Cleanup on exit
trap "kill $DEV_SERVER_PID $HOT_RELOAD_PID 2>/dev/null" EXIT

echo "Development environment running..."
echo "Dev server: http://localhost:3000"
echo "File watcher: monitoring src/ and static/"
echo "Press Ctrl+C to stop"

wait
```

### CI/CD Integration

```yaml
# .github/workflows/dev-workflow.yml
name: Development Workflow

on:
  push:
    branches: [develop]
  
jobs:
  test-hot-reload:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Zig
      uses: goto-bus-stop/setup-zig@v2
      with:
        version: 0.13.0
    
    - name: Build tools
      run: zig build tools
    
    - name: Test hot reloading
      run: |
        # Create test environment
        mkdir -p test-watch
        echo '{"test": "data"}' > test-watch/test.json
        
        # Start hot reloader in background
        ./zig-out/bin/hot-reloading --watch "test-watch/*.json" \
          --exec "echo 'File changed: {file}'" &
        WATCHER_PID=$!
        
        sleep 2
        
        # Modify file to trigger reload
        echo '{"test": "modified"}' > test-watch/test.json
        
        sleep 2
        
        # Cleanup
        kill $WATCHER_PID
        
        echo "Hot reloading test completed"
```

### Docker Development Environment

```dockerfile
# Dockerfile.dev
FROM ubuntu:latest

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# Copy tools
COPY zig-out/bin/hot-reloading /usr/local/bin/
COPY zig-out/bin/dev-server /usr/local/bin/
COPY zig-out/bin/zmin /usr/local/bin/

# Create working directory
WORKDIR /app

# Start development environment
CMD ["hot-reloading", "--watch", "/app/src/**/*.zig", "--exec", "zig build && dev-server 8080"]
```

```bash
# Docker usage
docker build -f Dockerfile.dev -t zmin-dev .
docker run -v $(pwd):/app -p 8080:8080 zmin-dev
```

## Advanced Workflow Examples

### JSON Data Processing Pipeline

```bash
#!/bin/bash
# json-processing-pipeline.sh

echo "Setting up JSON processing pipeline..."

# Create directory structure
mkdir -p {input,processing,output,archive}

# Stage 1: Watch for new input files
hot-reloading --watch "input/*.json" \
  --exec "mv {file} processing/ && echo 'File queued: {filename}'" &

# Stage 2: Process files in processing directory  
hot-reloading --watch "processing/*.json" \
  --debounce 1000 \
  --exec "zmin {file} --mode turbo --output output/{filename} && mv {file} archive/" &

# Stage 3: Monitor output for further processing
hot-reloading --watch "output/*.json" \
  --exec "debugger -i {file} --benchmark 5 > reports/{filename}.report" &

echo "JSON processing pipeline active"
echo "Drop files in input/ directory to process"

# Keep script running
wait
```

### Development Server with Auto-Restart

```bash
#!/bin/bash
# auto-restart-server.sh

SERVER_PID=""

start_server() {
    echo "Starting development server..."
    dev-server 8080 &
    SERVER_PID=$!
    echo "Server started with PID: $SERVER_PID"
}

restart_server() {
    if [ -n "$SERVER_PID" ]; then
        echo "Stopping server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null
        wait $SERVER_PID 2>/dev/null
    fi
    start_server
}

# Initial server start
start_server

# Watch for configuration changes
hot-reloading --watch "configs/*.json,src/**/*.zig" \
  --ignore "zig-out/**" \
  --debounce 2000 \
  --exec "zig build && restart_server" &

# Cleanup on exit
trap "kill $SERVER_PID 2>/dev/null" EXIT

echo "Auto-restart development server running"
echo "Monitoring configs/ and src/ for changes"
echo "Press Ctrl+C to stop"

wait
```

### Multi-Project Monitoring

```bash
#!/bin/bash
# multi-project-monitor.sh

PROJECTS=(
    "project1:/path/to/project1"
    "project2:/path/to/project2"
    "project3:/path/to/project3"
)

echo "Starting multi-project monitoring..."

for project in "${PROJECTS[@]}"; do
    IFS=':' read -r name path <<< "$project"
    
    echo "Monitoring $name at $path"
    
    # Start watcher for each project
    hot-reloading --watch "$path/src/**/*.zig" \
      --exec "cd '$path' && zig build && echo '$name: Build completed'" &
done

echo "All project monitors started"
wait
```

## Performance Monitoring Integration

### Resource Usage Monitoring

```bash
#!/bin/bash
# monitor-with-reloading.sh

echo "Starting resource monitoring with hot reloading..."

# Monitor system resources while watching files
{
    while true; do
        echo "$(date): CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}'), Memory: $(free -h | awk 'NR==2{print $3}')"
        sleep 5
    done
} &

# Watch files and trigger processing
hot-reloading --watch "data/*.json" \
  --debounce 1000 \
  --exec "profiler --input {file} --modes eco,sport,turbo" &

wait
```

### Performance-Aware File Processing

```bash
#!/bin/bash
# performance-aware-processing.sh

get_system_load() {
    uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//'
}

process_file() {
    local file="$1"
    local load=$(get_system_load)
    
    # Adjust processing based on system load
    if (( $(echo "$load < 1.0" | bc -l) )); then
        echo "Low load, using turbo mode for $file"
        zmin "$file" --mode turbo
    elif (( $(echo "$load < 2.0" | bc -l) )); then
        echo "Medium load, using sport mode for $file"
        zmin "$file" --mode sport
    else
        echo "High load, using eco mode for $file"
        zmin "$file" --mode eco
    fi
}

export -f process_file get_system_load

# Watch files with performance-aware processing
hot-reloading --watch "input/*.json" \
  --exec "process_file {file}"
```

## Troubleshooting Examples

### Debug Mode

```bash
# Enable debug mode for troubleshooting
hot-reloading --watch "*.json" \
  --exec "echo 'Processing {file}'" \
  --debug \
  --verbose

# Watch with detailed logging
hot-reloading --watch "src/**" \
  --log-file watcher.log \
  --debug
```

### Handle Watch Failures

```bash
#!/bin/bash
# robust-watcher.sh

start_watcher() {
    hot-reloading --watch "$1" --exec "$2" &
    WATCHER_PID=$!
    echo "Started watcher with PID: $WATCHER_PID"
}

monitor_watcher() {
    while true; do
        if ! kill -0 $WATCHER_PID 2>/dev/null; then
            echo "Watcher died, restarting..."
            start_watcher "$1" "$2"
        fi
        sleep 10
    done
}

# Start initial watcher
start_watcher "*.json" "zmin {file}"

# Monitor and restart if needed
monitor_watcher "*.json" "zmin {file}" &

# Cleanup on exit
trap "kill $WATCHER_PID 2>/dev/null" EXIT

wait
```

## Best Practices

1. **Use appropriate debounce times**: Prevent excessive rebuilds with reasonable delays
2. **Ignore build artifacts**: Exclude generated files from watching
3. **Monitor resource usage**: Watch system load when processing files
4. **Handle failures gracefully**: Implement restart mechanisms for robustness
5. **Use specific patterns**: Watch only necessary files to reduce overhead
6. **Test watch patterns**: Verify patterns match expected files
7. **Document workflows**: Clear documentation for complex watch setups
8. **Consider performance impact**: Balance responsiveness with system resources