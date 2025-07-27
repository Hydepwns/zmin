# zmin Node.js Native Addon

High-performance JSON minifier for Node.js using native C++ bindings.

## Installation

```bash
npm install zmin
```

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

```javascript
const zmin = require('zmin');

// Minify JSON string
const input = '{"name": "John", "age": 30, "city": "New York"}';
const minified = zmin.minify(input);
console.log(minified); // {"name":"John","age":30,"city":"New York"}

// Validate JSON
const isValid = zmin.validate(input);
console.log(isValid); // true
```

### Processing Modes

```javascript
// ECO mode - Low memory usage (64KB limit)
const ecoResult = zmin.minify(input, 0);

// SPORT mode - Balanced (default)
const sportResult = zmin.minify(input, 1);

// TURBO mode - Maximum performance
const turboResult = zmin.minify(input, 2);
```

### Using Minifier Instance

```javascript
// Create a reusable minifier
const minifier = new zmin.Zmin();

// Use it multiple times
const result1 = minifier.minify(input1, 2); // TURBO mode
const result2 = minifier.minify(input2, 1); // SPORT mode
```

## API Reference

### `zmin.minify(input: string, mode?: number): string`

Minifies JSON string by removing unnecessary whitespace.

**Parameters:**

- `input` - JSON string to minify
- `mode` - Processing mode (0=ECO, 1=SPORT, 2=TURBO, default=1)

**Returns:** Minified JSON string

**Throws:** Error if input is invalid JSON

### `zmin.validate(input: string): boolean`

Validates if a string is valid JSON.

**Parameters:**

- `input` - String to validate

**Returns:** `true` if valid JSON, `false` otherwise

### `zmin.getVersion(): string`

Returns the zmin library version.

### `new zmin.Zmin()`

Creates a new minifier instance.

**Methods:**

- `minify(input: string, mode?: number): string` - Minify JSON
- `validate(input: string): boolean` - Validate JSON
- `getVersion(): string` - Get library version

## Processing Modes

- **ECO (0)**: Memory-efficient mode with 64KB limit
- **SPORT (1)**: Balanced mode (default)
- **TURBO (2)**: Maximum performance mode

## Performance

This native addon provides near-native performance:

- **ECO**: 200-300 MB/s
- **SPORT**: 400-600 MB/s  
- **TURBO**: 800-1200 MB/s

## Error Handling

```javascript
try {
  const minified = zmin.minify(invalidJson);
} catch (error) {
  console.error('Minification failed:', error.message);
}
```

## Thread Safety

The zmin library is thread-safe. You can safely use it in worker threads:

```javascript
const { Worker } = require('worker_threads');

const worker = new Worker(`
  const { parentPort } = require('worker_threads');
  const zmin = require('zmin');
  
  parentPort.on('message', (data) => {
    const minified = zmin.minify(data, 2);
    parentPort.postMessage(minified);
  });
`, { eval: true });
```

## Building from Source

```bash
# Install dependencies
npm install

# Build the native addon
npm run build

# Run tests
npm test
```

## Platform Support

- Linux (x86_64, aarch64)
- macOS (x86_64, arm64)
- Windows (x86_64)

## License

MIT License - see [LICENSE](../../LICENSE) for details.
