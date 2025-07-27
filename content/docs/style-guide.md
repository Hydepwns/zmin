---
title: "Documentation Style Guide"
date: 2024-01-01
draft: false
weight: 10
---


This guide ensures consistency across all zmin documentation, from README files to API documentation.

## General Principles

### 1. **Clarity Over Completeness**
- Start with the most common use case
- Use concrete examples over abstract descriptions
- Provide working code that users can copy-paste

### 2. **Consistency**
- Use the same terminology throughout
- Follow established formatting patterns
- Maintain consistent performance claims

### 3. **Accuracy**
- All performance numbers must be verifiable
- Code examples must be tested
- Links must be functional

## Terminology Standards

### Core Terms

| Term | Usage | Don't Use |
|------|-------|-----------|
| **zmin** | Always lowercase, except at sentence start | ZMIN, Zmin, Z-min |
| **JSON minification** | Preferred description | JSON compression, JSON shrinking |
| **Throughput** | For performance metrics | Speed, rate |
| **Mode** | ECO, SPORT, TURBO (all caps) | eco, sport, turbo |
| **GPU acceleration** | Preferred over "GPU support" | GPU processing |

### Performance Metrics

**Always use these exact formats**:
- **Throughput**: `~312 MB/s`, `~555 MB/s`, `~1.1 GB/s`
- **Memory**: `64 KB`, `128 MB`, `1 GB` (space between number and unit)
- **File sizes**: `< 1 MB`, `100+ MB`, `1 GB` (use + for "or larger")
- **Compression**: `25.8%` (one decimal place)

**Performance Claims**:
- ECO mode: `~312 MB/s`
- SPORT mode: `~555 MB/s`
- TURBO mode: `~1.1 GB/s`
- GPU acceleration: `~2.0 GB/s`

## Document Structure

### README Files

Every README should follow this structure:

```markdown
# [Package Name]

[One-line description with performance claim]

## Installation

[Quickest install method first]

## Usage

### Basic Usage
[Simplest working example]

### [Advanced Features]
[More complex examples]

## API Reference
[If applicable]

## Performance
[Benchmarks specific to this binding]

## Documentation
- **[Main Documentation](https://zmin.droo.foo)** - Interactive guides and examples
- **[API Reference](https://zmin.droo.foo/api-reference)** - Complete API documentation
- **[Performance Guide](https://zmin.droo.foo/performance)** - Optimization tips

## License
MIT License - see [LICENSE](../../LICENSE) for details.
```

### Documentation Pages

Structure for `docs/` files:

```markdown
# [Page Title]

[Brief description and purpose]

## Overview
[High-level explanation]

## Quick Start
[Immediate working example]

## [Core Sections]
[Detailed information organized logically]

## Examples
[Real-world usage patterns]

## Troubleshooting
[Common issues and solutions]

## Advanced Topics
[Complex scenarios]

For more information, visit [zmin.droo.foo/[page]](https://zmin.droo.foo/[page]).
```

## Code Examples

### Command Line Examples

**Always use realistic filenames**:
```bash
# ✅ Good
zmin large-dataset.json minified.json

# ❌ Avoid
zmin input.json output.json
zmin file1.json file2.json
```

**Show expected output when helpful**:
```bash
zmin --verbose large-file.json output.json
# Output:
# Mode: TURBO
# Processing time: 1.1s
# Throughput: 1.09 GB/s
```

### API Examples

**Node.js**:
```javascript
// Always use const/require for zmin examples
const { minify } = require('@zmin/cli');

// Show realistic data
const apiResponse = {
  users: [/* ... */],
  metadata: { total: 1000, page: 1 }
};

const minified = minify(JSON.stringify(apiResponse));
```

**Python**:
```python
# Always import zmin explicitly
import zmin

# Use descriptive variable names
large_dataset = {"records": [/* ... */]}
minified_json = zmin.minify(large_dataset, mode=zmin.ProcessingMode.TURBO)
```

**Go**:
```go
// Use proper error handling
package main

import (
    "fmt"
    "log"
    "github.com/hydepwns/zmin/go"
)

func main() {
    data := `{"users": [...]}`
    
    result, err := zmin.MinifyWithMode(data, zmin.TURBO)
    if err != nil {
        log.Fatal(err)
    }
    
    fmt.Println(result)
}
```

## Version References

### Package Versions
- All packages use: `v1.0.0`
- Node.js engine requirement: `>=16.0.0`
- Python requirement: `>=3.8`
- Go requirement: `>=1.19`

### URLs and Links
- Main website: `https://zmin.droo.foo`
- GitHub repository: `https://github.com/hydepwns/zmin`
- Documentation sections: `https://zmin.droo.foo/[section]`

## Installation Instructions

### Standard Format

```markdown
## Installation

### From Package Manager
```bash
# Package manager command
```

### From Source
```bash
git clone https://github.com/hydepwns/zmin
cd zmin && zig build --release=fast
```

### Verification
```bash
zmin --version
echo '{"test": true}' | zmin
```
```

### Build Commands
Always use: `zig build --release=fast` (not just `zig build`)

## Performance Documentation

### Benchmark Tables

Use this exact format:

```markdown
| File Size | Throughput | Mode | Hardware |
|-----------|------------|------|----------|
| < 1 MB | ~312 MB/s | ECO | Single-threaded |
| 1-50 MB | ~555 MB/s | SPORT | Parallel |
| 50+ MB | ~1.1 GB/s | TURBO | SIMD + parallel |
| 100+ MB | ~2.0 GB/s | GPU | CUDA/OpenCL |
```

### Mode Descriptions

**Consistent descriptions**:
- **ECO**: Memory-efficient mode with 64KB limit
- **SPORT**: Balanced performance (default)
- **TURBO**: Maximum performance mode

## Error Handling Examples

### Show both success and error cases:

```javascript
try {
  const result = minify(jsonData);
  console.log('Minified successfully');
} catch (error) {
  console.error('Minification failed:', error.message);
  // Fallback to original data
}
```

## Cross-References

### Documentation Links

**Always include these sections in binding READMEs**:
```markdown
## Documentation

- **[Main Documentation](https://zmin.droo.foo)** - Interactive guides and examples
- **[API Reference](https://zmin.droo.foo/api-reference)** - Complete API documentation
- **[Performance Guide](https://zmin.droo.foo/performance)** - Optimization tips
```

### Internal Links
- Use relative paths for local docs: `[Usage Guide](usage.md)`
- Use full URLs for website links: `[Usage Guide](https://zmin.droo.foo/usage)`

## Language-Specific Guidelines

### Node.js
- Use `require()` syntax (not ES6 imports) for examples
- Always show error handling
- Include TypeScript definitions when available

### Python
- Use modern Python syntax (f-strings, type hints when helpful)
- Import `zmin` explicitly (not `from zmin import *`)
- Use enum constants: `zmin.ProcessingMode.TURBO`

### Go
- Always include proper error handling
- Use descriptive variable names
- Show complete working examples

### Zig
- Use `std.heap.page_allocator` for examples
- Include proper error handling with try/catch
- Show memory cleanup with defer

## Common Mistakes to Avoid

### ❌ Don't Do This

**Inconsistent performance claims**:
```markdown
# Bad - different numbers across docs
- "3.5+ GB/s throughput"
- "1-3 GB/s throughput"  
- "Up to 2 GB/s"
```

**Vague examples**:
```bash
# Bad - generic filenames
zmin input.json output.json

# Bad - no context
zmin file1.json file2.json
```

**Inconsistent package names**:
```bash
# Bad - wrong package
npm install zmin-cli

# Bad - wrong import path  
go get github.com/zmin/go
```

### ✅ Do This

**Consistent performance claims**:
```markdown
# Good - use verified benchmarks
- ECO: ~312 MB/s
- SPORT: ~555 MB/s  
- TURBO: ~1.1 GB/s
```

**Descriptive examples**:
```bash
# Good - realistic use case
zmin large-dataset.json compressed.json

# Good - shows purpose
zmin api-response.json minified-response.json
```

**Correct package references**:
```bash
# Good - correct packages
npm install @zmin/cli              # CLI package
npm install zmin                   # Native addon
go get github.com/hydepwns/zmin/go # Go bindings
```

## Review Checklist

Before publishing documentation, verify:

### Content
- [ ] Performance numbers match verified benchmarks
- [ ] All code examples are tested and work
- [ ] Package names and versions are correct
- [ ] URLs point to correct destinations
- [ ] Cross-references are consistent

### Format
- [ ] Headings follow hierarchy (# ## ### ####)
- [ ] Code blocks specify language
- [ ] Tables are properly formatted
- [ ] Lists use consistent bullet styles

### Style
- [ ] Terminology matches style guide
- [ ] Examples are realistic and helpful  
- [ ] Error handling is shown where appropriate
- [ ] Documentation links are included

## Automation

### Automated Checks

Consider these automated validations:

```bash
#!/bin/bash
# docs-lint.sh

# Check for consistent performance claims
grep -r "GB/s\|MB/s" docs/ | grep -v "~1.1 GB/s\|~555 MB/s\|~312 MB/s\|~2.0 GB/s" && echo "❌ Inconsistent performance claims"

# Check for placeholder URLs
grep -r "yourusername\|example\.com" docs/ && echo "❌ Placeholder URLs found"

# Check for consistent package names
grep -r "zmin-cli\|@zmin/zmin" docs/ && echo "❌ Incorrect package names"

# Validate links
find docs/ -name "*.md" -exec markdown-link-check {} \;
```

### Performance Validation

```bash
#!/bin/bash
# validate-benchmarks.sh

# Run actual benchmarks and compare with documented claims
echo "Validating performance claims..."

actual_eco=$(zmin --mode eco --benchmark test-file.json | grep "Throughput" | awk '{print $2}')
actual_sport=$(zmin --mode sport --benchmark test-file.json | grep "Throughput" | awk '{print $2}')
actual_turbo=$(zmin --mode turbo --benchmark test-file.json | grep "Throughput" | awk '{print $2}')

# Compare with documented values and warn if significantly different
```

## Maintenance

### Regular Reviews

- **Monthly**: Check all external links
- **Per release**: Update version numbers
- **Per benchmark**: Validate performance claims
- **Per feature**: Update examples and use cases

### Version Control

- Use semantic commit messages for documentation
- Tag documentation versions with releases
- Maintain changelog for major documentation updates

This style guide ensures zmin documentation remains consistent, accurate, and helpful across all platforms and use cases.