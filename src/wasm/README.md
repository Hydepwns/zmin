# zmin WebAssembly

This directory contains the WebAssembly build of zmin, allowing you to use the high-performance JSON minifier in web browsers and Node.js.

## Building

```bash
# Build the WebAssembly module
zig build-lib src/wasm/exports.zig -target wasm32-freestanding -dynamic -rdynamic -O ReleaseFast

# Or use the build script
zig build wasm
```

## Files

- `exports.zig` - WebAssembly exports and memory management
- `bindings.js` - JavaScript wrapper for easy usage
- `index.html` - Interactive demo page
- `README.md` - This file

## Usage

### Browser

```html
<script src="bindings.js"></script>
<script>
async function demo() {
    const zmin = new ZminWasm();
    await zmin.init('zmin.wasm');
    
    const input = '{"hello": "world", "test": true}';
    const output = zmin.minify(input);
    console.log(output); // {"hello":"world","test":true}
}
</script>
```

### Node.js

```javascript
const ZminWasm = require('./bindings.js');

async function demo() {
    const zmin = new ZminWasm();
    await zmin.init('./zmin.wasm');
    
    const input = require('fs').readFileSync('large.json', 'utf8');
    const output = zmin.minify(input, ZminWasm.Mode.TURBO);
    console.log(`Minified ${input.length} bytes to ${output.length} bytes`);
}
```

## API Reference

### `ZminWasm`

Main class for interacting with the WebAssembly module.

#### Methods

- `async init(wasmSource)` - Initialize the module
  - `wasmSource`: URL to .wasm file or WebAssembly.Instance

- `minify(input, mode)` - Minify JSON string
  - `input`: JSON string to minify
  - `mode`: Processing mode (ECO=0, SPORT=1, TURBO=2)
  - Returns: Minified JSON string

- `validate(input)` - Validate JSON without minifying
  - `input`: JSON string to validate
  - Returns: Boolean (true if valid)

- `getVersion()` - Get version string
  - Returns: Version string

- `getMemoryStats()` - Get memory usage statistics
  - Returns: Object with `used` and `max` properties

- `estimateOutputSize(inputSize)` - Estimate output buffer size
  - `inputSize`: Input size in bytes
  - Returns: Estimated output size

### Processing Modes

- `ZminWasm.Mode.ECO` (0) - Low memory mode (64KB limit)
- `ZminWasm.Mode.SPORT` (1) - Balanced mode (default)
- `ZminWasm.Mode.TURBO` (2) - Maximum performance mode

## Memory Management

The WebAssembly module uses a fixed 16MB memory buffer. For ECO mode, a separate 64KB buffer is allocated to respect the memory constraint.

Memory is automatically managed, but you can check usage:

```javascript
const stats = zmin.getMemoryStats();
console.log(`Using ${stats.used} of ${stats.max} bytes`);
```

## Performance

WebAssembly performance varies by browser and system:

- Chrome/Edge: Near-native performance with V8
- Firefox: Excellent performance with SpiderMonkey
- Safari: Good performance with JavaScriptCore
- Node.js: Best performance with V8

Typical throughput:
- ECO mode: 50-100 MB/s
- SPORT mode: 100-200 MB/s
- TURBO mode: 200-400 MB/s

## Error Handling

The module provides detailed error codes:

```javascript
try {
    const output = zmin.minify(input);
} catch (error) {
    console.error(error.message);
    // Error messages include:
    // - "Invalid JSON"
    // - "Out of memory"
    // - "Invalid mode"
}
```

## Demo

Open `index.html` in a web browser to see an interactive demo with:
- JSON minification with different modes
- Validation
- Pretty printing
- Performance benchmarking
- Memory usage tracking

## Browser Compatibility

- Chrome 57+
- Firefox 52+
- Safari 11+
- Edge 16+
- Node.js 8+ (with --experimental-wasm-modules)

## Security

The WebAssembly module runs in a sandboxed environment:
- No file system access
- No network access
- Fixed memory allocation
- No system calls

## Limitations

1. Maximum input size: ~15MB (due to fixed memory buffer)
2. No streaming support (entire input must fit in memory)
3. UTF-8 encoding only
4. No custom allocators

## Building Custom Configurations

To build with different memory sizes:

```zig
// In exports.zig, change:
var wasm_buffer: [32 * 1024 * 1024]u8 = undefined; // 32MB

// Rebuild:
zig build-lib src/wasm/exports.zig -target wasm32-freestanding -dynamic -O ReleaseSmall
```

## Integration Examples

### React

```jsx
import { useEffect, useState } from 'react';
import ZminWasm from './bindings.js';

function JsonMinifier() {
    const [zmin, setZmin] = useState(null);
    
    useEffect(() => {
        const init = async () => {
            const instance = new ZminWasm();
            await instance.init('/zmin.wasm');
            setZmin(instance);
        };
        init();
    }, []);
    
    const handleMinify = (input) => {
        if (!zmin) return;
        try {
            return zmin.minify(input);
        } catch (error) {
            console.error(error);
        }
    };
    
    // ... rest of component
}
```

### Web Worker

```javascript
// worker.js
importScripts('bindings.js');

let zmin = null;

self.addEventListener('message', async (e) => {
    if (e.data.type === 'init') {
        zmin = new ZminWasm();
        await zmin.init(e.data.wasmUrl);
        self.postMessage({ type: 'ready' });
    } else if (e.data.type === 'minify') {
        try {
            const output = zmin.minify(e.data.input, e.data.mode);
            self.postMessage({ type: 'result', output });
        } catch (error) {
            self.postMessage({ type: 'error', error: error.message });
        }
    }
});
```

## Contributing

To contribute to the WebAssembly build:

1. Modify `exports.zig` for new functionality
2. Update `bindings.js` with new methods
3. Add tests in `test_wasm.js`
4. Update documentation
5. Test in multiple browsers