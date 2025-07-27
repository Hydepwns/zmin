# zmin Python Bindings

High-performance JSON minifier for Python, powered by Zig.

## Installation

### From PyPI

```bash
pip install zmin
```

### From Source

```bash
# Build the shared library
cd ../..
zig build-lib -dynamic src/bindings/c_api.zig -lc

# Install Python package
cd bindings/python
pip install -e .
```

## Usage

### Basic Usage

```python
import zmin

# Minify JSON string
input_json = '{"name": "John", "age": 30, "city": "New York"}'
minified = zmin.minify(input_json)
print(minified)  # {"name":"John","age":30,"city":"New York"}

# Minify Python dict/list
data = {"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]}
minified = zmin.minify(data)

# Validate JSON
is_valid = zmin.validate(input_json)
print(f"Valid: {is_valid}")
```

### Processing Modes

```python
from zmin import ProcessingMode

# ECO mode - Low memory usage (64KB limit)
minified = zmin.minify(large_json, mode=ProcessingMode.ECO)

# SPORT mode - Balanced (default)
minified = zmin.minify(large_json, mode=ProcessingMode.SPORT)

# TURBO mode - Maximum performance
minified = zmin.minify(large_json, mode=ProcessingMode.TURBO)
```

### File Operations

```python
# Minify a file
zmin.minify_file('input.json', 'output.json', mode=ProcessingMode.TURBO)

# Validate a file
if zmin.validate_file('data.json'):
    print("File contains valid JSON")
```

### Advanced Usage

```python
# Create a custom instance
minifier = zmin.Zmin(lib_path='/custom/path/to/libzmin.so')

# Get version
version = minifier.get_version()
print(f"zmin version: {version}")

# Batch processing
import glob

for file_path in glob.glob('*.json'):
    output_path = file_path.replace('.json', '.min.json')
    try:
        minifier.minify_file(file_path, output_path, ProcessingMode.TURBO)
        print(f"Minified: {file_path}")
    except zmin.ZminError as e:
        print(f"Error processing {file_path}: {e}")
```

## Command Line Interface

```bash
# Minify a file
pyzmin input.json output.json

# Use different modes
pyzmin --mode turbo large.json compressed.json

# Validate only
pyzmin --validate data.json

# Show statistics
pyzmin --stats input.json output.json

# Read from stdin
echo '{"test": true}' | pyzmin

# Show version
pyzmin --version
```

## Performance

zmin is significantly faster than pure Python JSON minification:

```python
import json
import time
import zmin

# Large JSON data
with open('large.json', 'r') as f:
    data = json.load(f)

# Pure Python
start = time.time()
minified_py = json.dumps(data, separators=(',', ':'))
py_time = time.time() - start

# zmin
start = time.time()
minified_zmin = zmin.minify(data, ProcessingMode.TURBO)
zmin_time = time.time() - start

print(f"Python: {py_time:.3f}s")
print(f"zmin:   {zmin_time:.3f}s")
print(f"Speedup: {py_time/zmin_time:.1f}x")
```

## API Reference

### Functions

#### `minify(input_json, mode=ProcessingMode.SPORT) -> str`
Minify JSON data.

**Parameters:**
- `input_json`: JSON string, dict, or list
- `mode`: Processing mode (ECO, SPORT, or TURBO)

**Returns:** Minified JSON string

**Raises:** `ZminError` if minification fails

#### `validate(input_json) -> bool`
Validate JSON data.

**Parameters:**
- `input_json`: JSON string, dict, or list

**Returns:** True if valid JSON

#### `minify_file(input_path, output_path, mode=ProcessingMode.SPORT)`
Minify a JSON file.

#### `validate_file(file_path) -> bool`
Validate a JSON file.

### Classes

#### `Zmin`
Main class for JSON minification.

**Methods:**
- `__init__(lib_path=None)`: Initialize with optional library path
- `minify(input_json, mode)`: Minify JSON
- `validate(input_json)`: Validate JSON
- `get_version()`: Get library version
- `minify_file(input_path, output_path, mode)`: Minify file
- `validate_file(file_path)`: Validate file

#### `ProcessingMode`
Enum for processing modes:
- `ECO`: Memory-efficient mode (64KB limit)
- `SPORT`: Balanced mode (default)
- `TURBO`: Maximum performance mode

#### `ZminError`
Exception raised for minification errors.

## Error Handling

```python
try:
    minified = zmin.minify(invalid_json)
except zmin.ZminError as e:
    print(f"Minification failed: {e}")
```

## Thread Safety

The zmin library is thread-safe. You can use it in multi-threaded applications:

```python
import concurrent.futures
import zmin

def process_file(file_path):
    output_path = file_path.replace('.json', '.min.json')
    zmin.minify_file(file_path, output_path, zmin.ProcessingMode.TURBO)
    return file_path

files = ['file1.json', 'file2.json', 'file3.json']

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
    results = list(executor.map(process_file, files))
```

## Testing

```bash
# Install dev dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Run benchmarks
pytest --benchmark-only

# Type checking
mypy zmin.py

# Linting
flake8 zmin.py
black --check zmin.py
```

## Building the Shared Library

The Python bindings require the zmin shared library. Build it with:

```bash
# Linux
zig build-lib -dynamic -lc src/bindings/c_api.zig -femit-bin=libzmin.so

# macOS
zig build-lib -dynamic -lc src/bindings/c_api.zig -femit-bin=libzmin.dylib

# Windows
zig build-lib -dynamic -lc src/bindings/c_api.zig -femit-bin=zmin.dll
```

## Platform Support

- Linux (x86_64, aarch64)
- macOS (x86_64, arm64)
- Windows (x86_64)

## License

MIT License - see LICENSE file for details.