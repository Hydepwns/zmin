# zmin Go Bindings

High-performance JSON minifier for Go, powered by Zig.

## Installation

```bash
go get github.com/hydepwns/zmin/go

## Prerequisites

The zmin shared library must be available:

```bash
# Build the shared library
cd ../..
zig build-lib -dynamic src/bindings/c_api.zig -lc

# Install to system (Linux/macOS)
sudo cp libzmin.so /usr/local/lib/  # Linux
sudo cp libzmin.dylib /usr/local/lib/  # macOS
sudo ldconfig  # Linux only
```

## Usage

### Basic Usage

```go
package main

import (
    "fmt"
    "log"
    "github.com/hydepwns/zmin/go"
)

func main() {
    // Minify JSON string
    input := `{
        "name": "John Doe",
        "age": 30,
        "city": "New York"
    }`
    
    output, err := zmin.Minify(input)
    if err != nil {
        log.Fatal(err)
    }
    
    fmt.Println(output)
    // Output: {"name":"John Doe","age":30,"city":"New York"}
    
    // Validate JSON
    if zmin.Validate(input) {
        fmt.Println("Valid JSON")
    }
}
```

### Processing Modes

```go
// ECO mode - Low memory usage (64KB limit)
output, err := zmin.MinifyWithMode(input, zmin.ECO)

// SPORT mode - Balanced (default)
output, err := zmin.MinifyWithMode(input, zmin.SPORT)

// TURBO mode - Maximum performance
output, err := zmin.MinifyWithMode(input, zmin.TURBO)
```

### Working with Different Input Types

```go
// Minify from struct
data := map[string]interface{}{
    "users": []map[string]interface{}{
        {"id": 1, "name": "Alice"},
        {"id": 2, "name": "Bob"},
    },
}
output, err := zmin.Minify(data)

// Minify from bytes
jsonBytes := []byte(`{"test": true}`)
outputBytes, err := zmin.MinifyBytes(jsonBytes, zmin.TURBO)

// Minify from io.Reader
file, err := os.Open("input.json")
if err != nil {
    log.Fatal(err)
}
defer file.Close()
output, err := zmin.MinifyReader(file, zmin.SPORT)
```

### File Operations

```go
// Minify a file
err := zmin.MinifyFile("input.json", "output.json", zmin.TURBO)
if err != nil {
    log.Fatal(err)
}

// Validate a file
if zmin.ValidateFile("data.json") {
    fmt.Println("File contains valid JSON")
}
```

### Using Minifier Instance

```go
// Create a reusable minifier
minifier := zmin.NewMinifier(zmin.TURBO)

// Use it multiple times
for _, file := range files {
    output, err := minifier.Minify(file)
    if err != nil {
        log.Printf("Error: %v", err)
        continue
    }
    // Process output...
}

// Pre-configured minifiers
output1, _ := zmin.EcoMinifier.Minify(input)
output2, _ := zmin.SportMinifier.Minify(input)
output3, _ := zmin.TurboMinifier.Minify(input)
```

## Performance

Benchmark comparing zmin with standard library JSON encoding:

```go
package main

import (
    "encoding/json"
    "testing"
    "github.com/hydepwns/zmin/go"
)

func BenchmarkStdJSON(b *testing.B) {
    data := generateLargeJSON()
    
    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        output, _ := json.Marshal(data)
        _ = output
    }
}

func BenchmarkZmin(b *testing.B) {
    data := generateLargeJSON()
    jsonStr, _ := json.Marshal(data)
    
    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        output, _ := zmin.MinifyWithMode(jsonStr, zmin.TURBO)
        _ = output
    }
}
```

Typical results:

- Standard library: 50-100 MB/s
- zmin ECO: ~1.5 GB/s
- zmin SPORT: ~3.5 GB/s
- zmin TURBO: ~5+ GB/s

## API Reference

### Constants

```go
const (
    ECO   ProcessingMode = 0  // Memory-efficient mode
    SPORT ProcessingMode = 1  // Balanced mode
    TURBO ProcessingMode = 2  // Maximum performance
)
```

### Functions

#### `Minify(input interface{}) (string, error)`

Minifies JSON using default SPORT mode.

#### `MinifyWithMode(input interface{}, mode ProcessingMode) (string, error)`

Minifies JSON using specified mode.

#### `Validate(input interface{}) bool`

Validates JSON data.

#### `MinifyBytes(input []byte, mode ProcessingMode) ([]byte, error)`

Minifies JSON from bytes.

#### `MinifyReader(r io.Reader, mode ProcessingMode) (string, error)`

Minifies JSON from io.Reader.

#### `MinifyFile(inputPath, outputPath string, mode ProcessingMode) error`

Minifies a JSON file.

#### `ValidateFile(filePath string) bool`

Validates a JSON file.

#### `Version() string`

Returns zmin library version.

### Types

#### `ProcessingMode`

Processing mode for minification.

#### `Minifier`

Reusable minifier instance.

### Errors

```go
var (
    ErrInvalidJSON = errors.New("invalid JSON")
    ErrOutOfMemory = errors.New("out of memory")
    ErrInvalidMode = errors.New("invalid mode")
    ErrUnknown     = errors.New("unknown error")
)
```

## Thread Safety

The zmin library is thread-safe. You can safely use it in goroutines:

```go
var wg sync.WaitGroup
files := []string{"file1.json", "file2.json", "file3.json"}

for _, file := range files {
    wg.Add(1)
    go func(f string) {
        defer wg.Done()
        
        err := zmin.MinifyFile(f, f+".min", zmin.TURBO)
        if err != nil {
            log.Printf("Error processing %s: %v", f, err)
        }
    }(file)
}

wg.Wait()
```

## Error Handling

```go
output, err := zmin.Minify(input)
if err != nil {
    switch err {
    case zmin.ErrInvalidJSON:
        // Handle invalid JSON
    case zmin.ErrOutOfMemory:
        // Try ECO mode
        output, err = zmin.MinifyWithMode(input, zmin.ECO)
    default:
        // Handle other errors
    }
}
```

## Building the Shared Library

### Linux

```bash
zig build-lib -dynamic -lc src/bindings/c_api.zig -femit-bin=libzmin.so
sudo cp libzmin.so /usr/local/lib/
sudo ldconfig
```

### macOS

```bash
zig build-lib -dynamic -lc src/bindings/c_api.zig -femit-bin=libzmin.dylib
sudo cp libzmin.dylib /usr/local/lib/
```

### Windows

```bash
zig build-lib -dynamic -lc src/bindings/c_api.zig -femit-bin=zmin.dll
# Add to PATH or copy to executable directory
```

## CGO Flags

If the library is in a non-standard location:

```go
// #cgo CFLAGS: -I/path/to/headers
// #cgo LDFLAGS: -L/path/to/lib -lzmin
```

## Testing

```bash
go test
go test -bench=.
go test -race
```

## Examples

See the [examples](examples/) directory for more usage examples:

- `basic/` - Basic usage examples
- `streaming/` - Processing large files
- `server/` - HTTP server with JSON minification
- `cli/` - Command-line tool

## Documentation

- **[Main Documentation](https://zmin.droo.foo)** - Interactive guides and examples
- **[API Reference](https://zmin.droo.foo/api-reference)** - Complete API documentation
- **[Performance Guide](https://zmin.droo.foo/performance)** - Optimization tips

## License

MIT License - see LICENSE file for details.
