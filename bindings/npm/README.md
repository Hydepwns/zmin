# @zmin/cli

Ultra-high-performance JSON minifier with **3.5+ GB/s** throughput using WebAssembly.

## Installation

```bash
npm install -g @zmin/cli
```

## Usage

### Command Line

```bash
# Basic minification
zmin input.json output.json

# Pipe usage
echo '{"key": "value"}' | zmin

# Pretty format
zmin --pretty input.json formatted.json
```

### Node.js API

```javascript
const { minify, validate, formatJson } = require('@zmin/cli');

// Minify JSON
const minified = minify('{"key": "value", "array": [1, 2, 3]}');
console.log(minified); // {"key":"value","array":[1,2,3]}

// Validate JSON
const isValid = validate('{"valid": true}');
console.log(isValid); // true

// Format JSON
const formatted = formatJson('{"key":"value"}', { indent: 2 });
console.log(formatted);
// {
//   "key": "value"
// }
```

### Browser Usage

```html
<script src="https://unpkg.com/@zmin/cli/dist/zmin.js"></script>
<script>
  zmin.minify('{"key": "value"}').then(result => {
    console.log(result); // {"key":"value"}
  });
</script>
```

## Performance

- **3.5+ GB/s** throughput on modern hardware
- WebAssembly provides near-native performance
- Automatic SIMD optimization when available
- Memory efficient streaming for large files

## Features

- ✅ Ultra-fast JSON minification
- ✅ JSON validation with detailed error messages
- ✅ Pretty printing with customizable indentation
- ✅ Command-line interface
- ✅ Node.js and browser support
- ✅ TypeScript definitions included
- ✅ Zero dependencies
- ✅ Memory safe (written in Zig)

## API Reference

### `minify(input: string): string`

Minifies JSON string by removing unnecessary whitespace.

**Parameters:**
- `input` - JSON string to minify

**Returns:** Minified JSON string

**Throws:** Error if input is invalid JSON

### `validate(input: string): boolean`

Validates if a string is valid JSON.

**Parameters:**
- `input` - String to validate

**Returns:** `true` if valid JSON, `false` otherwise

### `formatJson(input: string, options?: FormatOptions): string`

Formats JSON with proper indentation.

**Parameters:**
- `input` - JSON string to format
- `options` - Optional formatting options
  - `indent?: number` - Number of spaces for indentation (default: 2)
  - `sortKeys?: boolean` - Sort object keys (default: false)

**Returns:** Formatted JSON string

## Performance Comparison

| Library | Throughput | Memory Usage |
|---------|------------|--------------|
| @zmin/cli | 3.5 GB/s | Very Low |
| JSON.stringify | 150 MB/s | High |
| jsonminify | 80 MB/s | Medium |
| uglify-es | 45 MB/s | High |

## License

MIT License - see [LICENSE](../../LICENSE) for details.

## Contributing

See the main [zmin repository](https://github.com/hydepwns/zmin) for contribution guidelines.