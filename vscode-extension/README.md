# zmin VS Code Extension

High-performance JSON minification with zmin integration for Visual Studio Code.

## Features

- **JSON Minification**: Minify entire files or selections with a single command
- **Performance Modes**: Choose between Eco, Sport, and Turbo modes
- **Benchmarking**: Test performance on your JSON files
- **Validation**: Validate JSON syntax using zmin
- **Auto-minify**: Optionally minify JSON files on save
- **Zig Syntax Highlighting**: Basic syntax highlighting for Zig files

## Requirements

- zmin must be installed and available in your PATH
- Or configure the path to zmin executable in settings

## Installation

1. Install zmin: `brew install zmin` (or build from source)
2. Install this extension from the VS Code marketplace
3. Configure settings as needed

## Usage

### Commands

- `zmin: Minify JSON` - Minify the current JSON file
- `zmin: Minify Selected JSON` - Minify only the selected JSON
- `zmin: Validate JSON` - Check if the current file is valid JSON
- `zmin: Benchmark JSON File` - Run performance benchmarks
- `zmin: Configure zmin` - Quick access to zmin settings

### Context Menu

Right-click on:
- JSON files in the editor to minify
- Selected JSON text to minify selection
- JSON files in the explorer to minify

### Keyboard Shortcuts

You can add custom keyboard shortcuts for any command in VS Code settings.

## Extension Settings

- `zmin.executable`: Path to zmin executable (default: "zmin")
- `zmin.mode`: Performance mode - eco, sport, or turbo (default: "sport")
- `zmin.enableGpu`: Enable GPU acceleration if available (default: false)
- `zmin.streaming`: Use streaming mode for large files (default: false)
- `zmin.autoMinifyOnSave`: Automatically minify JSON files on save (default: false)
- `zmin.showBenchmarks`: Show performance metrics after minification (default: true)

## Performance Modes

- **Eco**: Balanced performance and memory usage (~3 GB/s)
- **Sport**: Optimized for speed (default, ~4 GB/s)
- **Turbo**: Maximum performance with all optimizations (~5+ GB/s)

## Examples

### Minify a file
1. Open a JSON file
2. Press `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Windows/Linux)
3. Type "zmin: Minify JSON"
4. The minified file will be created as `filename.min.json`

### Minify selection
1. Select JSON text in the editor
2. Right-click and choose "Minify Selected JSON"
3. The selection will be replaced with minified JSON

### Benchmark performance
1. Open a JSON file
2. Run "zmin: Benchmark JSON File"
3. View results in the Output panel (zmin channel)

## Known Issues

- Large files (>100MB) may take a moment to process
- GPU acceleration requires compatible hardware

## Release Notes

### 1.0.0

Initial release:
- JSON minification commands
- Performance mode selection
- Benchmarking support
- Zig syntax highlighting
- Auto-minify on save option