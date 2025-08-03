# Development Tools

This directory contains various development and debugging tools for zmin.

## Available Tools

### config-manager

Configuration management utility for zmin build system.

**Usage:**

```bash
config-manager [command] [options]

Commands:
  show           - Show current configuration
  reset          - Reset to default configuration
  validate       - Validate configuration files
  set <key> <val>- Set configuration value
  get <key>      - Get configuration value
  profile list   - List available profiles
  profile apply  - Apply a configuration profile
```

### hot-reloading

Advanced file watching and build automation tool.

**Usage:**

```bash
hot-reloading [OPTIONS] [PATHS...]

Options:
  -b, --build-command <CMD>   Build command to run (default: "zig build")
  -v, --verbose               Enable verbose output with detailed stats
  -d, --debounce <MS>         Debounce time in milliseconds (default: 200)
      --no-clear              Don't clear console between builds
  -h, --help                  Show this help message
```

### dev-server

Development server with live minification and performance monitoring.

**Usage:**

```bash
dev-server [port]

Features:
- Live JSON minification via web interface
- Real-time performance monitoring
- System statistics dashboard
- API endpoints for programmatic access
```

### profiler

Performance profiling tool for zmin operations.

**Usage:**

```bash
profiler [OPTIONS]

Options:
  --input, -i <file>     Input file to process
  --output, -o <file>    Output file for minified result
  --json, -j <file>      Export profile to JSON file
  --iterations, -n <num> Number of iterations (default: 100)
  --help, -h             Show help
```

### debugger

Advanced debugging and system information tool.

**Usage:**

```bash
debugger [OPTIONS] [INPUT_FILE]

Options:
  --mode, -m <mode>       Processing mode (eco/sport/turbo)
  --output, -o <file>     Output file for results
  --level, -l <level>     Debug level (none/basic/verbose/trace)
  --iterations, -n <num>  Number of iterations for profiling
  --memory, -M            Enable memory tracking
  --stack-trace, -s       Enable stack traces
  --report, -r <file>     Generate HTML report
  --json, -j <file>       Export debug data as JSON
  --help, -h              Show help
```

### plugin-registry

Plugin management and registry tool.

**Usage:**

```bash
plugin-registry [command]

Commands:
  list      - List all registered plugins
  discover  - Discover plugins in standard locations
  load      - Load all discovered plugins
  test      - Test all loaded plugins
  info <N>  - Show detailed info for plugin N
  benchmark - Benchmark plugin performance
```

## Building the Tools

The dev tools are built automatically as part of the main build:

```bash
zig build
```

The compiled tools will be available in `zig-out/bin/`.

## Development

When adding new dev tools:

1. Create the tool in the `tools/` directory
2. Add it to `build/tools.zig` in the `dev_tools` array
3. Import any necessary modules (typically `zmin_lib`)
4. Update this documentation
