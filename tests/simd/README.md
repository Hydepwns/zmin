# SIMD Tests

This directory contains unit tests for SIMD-optimized JSON parsing components.

## Files

- `test_string_simd.zig` - Tests for AVX-512 vectorized string parsing
- `test_number_simd.zig` - Tests for AVX-512 vectorized number parsing

## Running Tests

```bash
# Run string parsing tests
zig run tests/simd/test_string_simd.zig

# Run number parsing tests  
zig run tests/simd/test_number_simd.zig
```

## Features Tested

### String Parsing
- ✅ Simple strings
- ✅ Long strings (>64 characters) that trigger SIMD processing
- ✅ Strings with escape sequences
- ✅ Empty strings
- ✅ Unicode strings
- ✅ JSON objects and arrays with strings

### Number Parsing
- ✅ Simple integers
- ✅ Negative numbers
- ✅ Decimal numbers
- ✅ Scientific notation (e/E)
- ✅ JSON objects and arrays with numbers
- ✅ Mixed number formats

## SIMD Optimizations

The tests verify that the AVX-512 implementation correctly:
- Processes 64-byte chunks with vector operations
- Handles edge cases with scalar fallback
- Maintains correctness across all input types
- Provides performance benefits for large inputs