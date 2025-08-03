# zmin Coding Standards

This document outlines the coding standards and best practices for the zmin JSON minifier project.

## Table of Contents
1. [General Principles](#general-principles)
2. [Code Organization](#code-organization)
3. [Naming Conventions](#naming-conventions)
4. [Error Handling](#error-handling)
5. [Performance Guidelines](#performance-guidelines)
6. [Documentation Standards](#documentation-standards)
7. [Testing Standards](#testing-standards)

## General Principles

### 1. Clarity Over Cleverness
- Write code that is easy to understand and maintain
- Prefer explicit over implicit behavior
- Avoid magic numbers and string literals

### 2. Performance with Safety
- Optimize for performance but never compromise memory safety
- Use compile-time verification where possible
- Profile before optimizing

### 3. Consistency
- Follow existing patterns in the codebase
- Use consistent formatting (enforce with `zig fmt`)
- Maintain consistent error handling patterns

## Code Organization

### File Structure
```
src/
├── api/           # Public API modules
├── core/          # Core minification engine
├── platform/      # Platform-specific code
├── utils/         # Utility functions
└── tests/         # Test files
```

### Module Guidelines
- Each module should have a single, well-defined purpose
- Keep modules under 500 lines when possible
- Use `pub` only for truly public APIs
- Group related functionality together

### Import Order
```zig
// 1. Standard library
const std = @import("std");
const builtin = @import("builtin");

// 2. External dependencies (if any)

// 3. Internal modules (grouped by category)
const platform = @import("../platform/arch_detector.zig");
const utils = @import("../utils/validation.zig");

// 4. Type aliases and constants
const Allocator = std.mem.Allocator;
```

## Naming Conventions

### General Rules
- Use `snake_case` for variables and functions
- Use `PascalCase` for types and structs
- Use `SCREAMING_SNAKE_CASE` for compile-time constants
- Prefix private fields with underscore in public structs

### Examples
```zig
// Constants
const MAX_BUFFER_SIZE = 1024 * 1024;
const DEFAULT_CHUNK_SIZE = 8192;

// Types
const MinifierEngine = struct {
    allocator: Allocator,
    _internal_buffer: []u8,  // Private field
    
    // Methods
    pub fn minify(self: *MinifierEngine, input: []const u8) ![]u8 {
        // ...
    }
};

// Functions
pub fn detect_hardware_capabilities() HardwareCapabilities {
    // ...
}

// Variables
var buffer_size: usize = 0;
const is_valid = try validateJSON(input);
```

## Error Handling

### Error Sets
Define specific error sets for each module:
```zig
pub const MinifierError = error{
    InvalidJson,
    BufferTooSmall,
    AllocationFailed,
    UnsupportedEncoding,
};
```

### Error Handling Patterns
```zig
// Always handle allocation failures
const buffer = allocator.alloc(u8, size) catch |err| switch (err) {
    error.OutOfMemory => return MinifierError.AllocationFailed,
};

// Provide context in error messages
if (!isValid(input)) {
    std.log.err("Invalid JSON at position {}: expected '{s}'", .{ pos, expected });
    return MinifierError.InvalidJson;
}

// Use error unions for fallible operations
pub fn minify(allocator: Allocator, input: []const u8) ![]u8 {
    // ...
}
```

## Performance Guidelines

### Memory Management
```zig
// Prefer stack allocation for small, fixed-size data
var buffer: [1024]u8 = undefined;

// Use arena allocators for temporary allocations
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

// Pre-allocate when size is known
var list = try ArrayList(u8).initCapacity(allocator, estimated_size);
```

### SIMD and Vectorization
```zig
// Use explicit vector types for SIMD operations
const Vector32 = @Vector(32, u8);

// Check capabilities before using SIMD
if (hardware_caps.has_avx2) {
    return processAVX2(input);
} else {
    return processScalar(input);
}
```

### Optimization Checklist
- [ ] Profile before optimizing
- [ ] Minimize allocations in hot paths
- [ ] Use appropriate data structures
- [ ] Consider cache locality
- [ ] Benchmark different approaches

## Documentation Standards

### Module Documentation
```zig
//! Module: JSON Minifier Core Engine
//! 
//! This module provides the core minification functionality with
//! adaptive strategy selection based on input characteristics.
//!
//! Features:
//! - Automatic optimization selection
//! - Hardware-aware processing
//! - Memory-safe operations
```

### Function Documentation
```zig
/// Minifies JSON input with automatic optimization selection.
/// 
/// This function analyzes input characteristics and selects the
/// optimal processing strategy based on size, structure, and
/// available hardware capabilities.
///
/// Parameters:
///   - allocator: Memory allocator for output buffer
///   - input: JSON string to minify
///   - options: Optional configuration (null for defaults)
/// 
/// Returns:
///   - Minified JSON string (caller owns memory)
/// 
/// Errors:
///   - InvalidJson: Input is not valid JSON
///   - OutOfMemory: Allocation failed
pub fn minify(allocator: Allocator, input: []const u8, options: ?Config) ![]u8 {
    // ...
}
```

### Inline Comments
```zig
// Use inline comments sparingly for complex logic
const mask = 0x80808080; // Check high bit of each byte

// Explain non-obvious optimizations
// Unroll loop 4x for better instruction pipelining
for (chunks) |chunk| {
    process(chunk[0]);
    process(chunk[1]); 
    process(chunk[2]);
    process(chunk[3]);
}
```

## Testing Standards

### Test Organization
```zig
test "minify removes whitespace outside strings" {
    const input = "{ \"key\" : \"value\" }";
    const expected = "{\"key\":\"value\"}";
    
    const result = try minify(testing.allocator, input, null);
    defer testing.allocator.free(result);
    
    try testing.expectEqualStrings(expected, result);
}
```

### Test Categories
1. **Unit Tests**: Test individual functions
2. **Integration Tests**: Test module interactions
3. **Performance Tests**: Benchmark critical paths
4. **Fuzz Tests**: Test with random/malformed input
5. **Property Tests**: Verify invariants

### Test Best Practices
- Test both success and failure cases
- Use descriptive test names
- Keep tests focused and isolated
- Mock external dependencies
- Test edge cases and boundaries

## Code Review Checklist

Before submitting code:
- [ ] Run `zig fmt` on all files
- [ ] Ensure all tests pass
- [ ] Add/update documentation
- [ ] Check for memory leaks
- [ ] Profile performance-critical changes
- [ ] Review error handling
- [ ] Verify thread safety (if applicable)

## Version Control

### Commit Messages
```
type(scope): subject

body

footer
```

Types: feat, fix, docs, style, refactor, perf, test, chore

Example:
```
perf(simd): optimize whitespace detection with AVX-512

- Add AVX-512 specific path for 64-byte processing
- Improve throughput by 15% on Intel Ice Lake
- Maintain compatibility with older CPUs

Benchmark: 3.2 GB/s -> 3.7 GB/s
```

## Conclusion

These standards ensure code quality, maintainability, and performance. They should be treated as guidelines rather than rigid rules - use judgment and prioritize clarity and correctness.