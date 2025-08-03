# zmin GitHub Action

High-performance JSON minification for your CI/CD pipeline using zmin.

## Features

- 🚀 **5+ GB/s throughput** - Fastest JSON minification available
- 🎯 **Multiple performance modes** - Eco, Sport, and Turbo
- 📁 **Batch processing** - Minify multiple files with glob patterns
- 📊 **Performance metrics** - Track size reduction and processing time
- 🔧 **Flexible configuration** - Customize output paths and behavior

## Usage

### Basic Example

```yaml
name: Minify JSON
on: [push, pull_request]

jobs:
  minify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Minify JSON files
        uses: hydepwns/zmin-action@v1
        with:
          files: '**/*.json'
          mode: 'sport'
```

### Advanced Example

```yaml
name: Build and Minify
on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build project
        run: npm run build
      
      - name: Minify production JSON
        uses: hydepwns/zmin-action@v1
        with:
          files: 'dist/**/*.json'
          mode: 'turbo'
          output-dir: 'dist-minified'
          exclude: '**/*.min.json,**/config.json'
          preserve-structure: true
          benchmark: true
      
      - name: Display results
        run: |
          echo "Files processed: ${{ steps.minify.outputs.total-files }}"
          echo "Space saved: ${{ steps.minify.outputs.total-saved }} bytes"
          echo "Average reduction: ${{ steps.minify.outputs.average-reduction }}%"
          echo "Processing time: ${{ steps.minify.outputs.processing-time }}ms"
      
      - name: Deploy minified files
        run: |
          # Deploy your minified files
          cp -r dist-minified/* dist/
```

### Matrix Build Example

```yaml
name: Test Multiple Modes
on: [push]

jobs:
  test:
    strategy:
      matrix:
        mode: [eco, sport, turbo]
        os: [ubuntu-latest, macos-latest, windows-latest]
    
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v3
      
      - name: Minify with ${{ matrix.mode }} mode
        uses: hydepwns/zmin-action@v1
        with:
          files: 'test-data/*.json'
          mode: ${{ matrix.mode }}
          benchmark: true
```

## Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `files` | JSON files to minify (glob pattern) | `**/*.json` | No |
| `mode` | Performance mode: `eco`, `sport`, or `turbo` | `sport` | No |
| `output-dir` | Output directory for minified files | `minified` | No |
| `exclude` | Files to exclude (glob pattern) | `**/node_modules/**,**/vendor/**` | No |
| `preserve-structure` | Preserve directory structure in output | `true` | No |
| `fail-on-error` | Fail the action if any file fails to minify | `true` | No |
| `version` | zmin version to use | `latest` | No |
| `benchmark` | Show performance benchmarks | `false` | No |

## Outputs

| Output | Description |
|--------|-------------|
| `total-files` | Total number of files processed |
| `total-saved` | Total bytes saved |
| `average-reduction` | Average size reduction percentage |
| `processing-time` | Total processing time in milliseconds |

## Performance Modes

### Eco Mode
- Balanced performance and memory usage
- ~3 GB/s throughput
- Lowest memory footprint
- Best for CI environments with resource constraints

### Sport Mode (Default)
- Optimized for speed
- ~4 GB/s throughput
- Moderate memory usage
- Recommended for most use cases

### Turbo Mode
- Maximum performance
- 5+ GB/s throughput
- SIMD optimizations enabled
- Best for large files and powerful runners

## Examples

### Minify API responses

```yaml
- name: Minify API responses
  uses: hydepwns/zmin-action@v1
  with:
    files: 'api/responses/**/*.json'
    output-dir: 'api/responses-min'
    mode: 'turbo'
```

### Minify build artifacts

```yaml
- name: Minify build artifacts
  uses: hydepwns/zmin-action@v1
  with:
    files: 'build/**/*.json'
    exclude: 'build/**/*.min.json'
    preserve-structure: true
```

### Conditional minification

```yaml
- name: Minify for production
  if: github.ref == 'refs/heads/main'
  uses: hydepwns/zmin-action@v1
  with:
    files: 'dist/**/*.json'
    mode: 'turbo'
```

## Performance Tips

1. **Use Turbo mode** for best performance on GitHub-hosted runners
2. **Batch files** together rather than running the action multiple times
3. **Exclude already minified files** to avoid reprocessing
4. **Use matrix builds** to test different modes in parallel

## Troubleshooting

### No files found
- Check your glob pattern matches files in the repository
- Ensure files aren't excluded by the `exclude` pattern
- Use `actions/checkout@v3` before this action

### Permission denied
- Ensure the output directory is writable
- Check file permissions in your repository

### Out of memory
- Use Eco mode for very large files
- Process files in smaller batches

## License

MIT - See [LICENSE](LICENSE) for details.