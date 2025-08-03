# zmin v2.0 Streaming Engine - Architectural Analysis

## Overview

This document provides a comprehensive analysis of the v2.0 streaming transformation engine architecture, identifying current limitations, performance bottlenecks, and paths to achieve the **10+ GB/s throughput target**.

## Current Status (Foundation Complete)

### ✅ **Working Components**

1. **Character-Based Minifier** (`src/v2/char_minifier.zig`)
   - **Performance**: 121+ MB/s sustained throughput
   - **Compression**: 62-80% size reduction
   - **Status**: Production-ready, comprehensive test coverage

2. **Memory Management** (`src/v2/streaming/parser.zig`)
   - **Memory Pool**: Efficient allocation with reset capability
   - **Zero-Copy**: Token streams reference original input data
   - **Status**: Working, needs optimization for high-throughput scenarios

3. **Token Stream Infrastructure** (`src/v2/streaming/parser.zig`)
   - **TokenStream**: ArrayList-based token storage
   - **Token**: Complete metadata (type, position, line, column)
   - **Status**: Functional but not optimized for speed

### ⚠️ **Architectural Issues**

## Issue 1: Comptime Function Pointer Limitations

**Problem**: The transformation pipeline cannot be instantiated at runtime due to function pointer requirements.

```zig
// This causes comptime-only evaluation:
pub const CustomTransformation = struct {
    transform: TransformFunction,     // Function pointer forces comptime
    cleanup: ?CleanupFunction = null, // Function pointer forces comptime
};
```

**Impact**: 
- `ZminEngine.init()` fails at runtime
- Transformation pipeline unusable for dynamic configurations
- Blocks integration testing and production usage

**Solution Path**:
```zig
// Replace function pointers with tagged unions
pub const CustomTransformation = struct {
    transform_type: TransformType,
    user_data: ?*anyopaque = null,
};

pub const TransformType = enum {
    minify_whitespace,
    filter_fields,
    validate_schema,
    custom_callback,
};
```

## Issue 2: SIMD Detection Incompatibility

**Problem**: Current SIMD level detection uses incompatible Zig APIs.

```zig
// This fails compilation:
if (target.cpu.features.isEnabled(@enumFromInt(std.Target.x86.Feature.avx512f))) {
    // Enum expected, u9 found
}
```

**Impact**:
- SIMD optimizations disabled
- Missing 5-10x performance potential
- Falls back to scalar processing only

**Solution Path**:
```zig
// Use builtin target detection
const builtin = @import("builtin");
const cpu_features = builtin.cpu.features;

// Check specific instruction sets
if (comptime cpu_features.avx512f) {
    // AVX-512 path
} else if (comptime cpu_features.avx2) {
    // AVX2 path  
} else {
    // Scalar fallback
}
```

## Issue 3: Performance Bottlenecks

### Current Throughput Analysis

| Component | Current Speed | Target Speed | Gap |
|-----------|---------------|--------------|-----|
| Character Minifier | 121 MB/s | 10,000 MB/s | 82x |
| Token Parser | Not measured | 10,000 MB/s | N/A |
| Memory Pool | Adequate | High-speed | Minor |

### Bottleneck Identification

1. **Single-threaded Processing**
   - Current: Sequential character-by-character processing
   - Needed: SIMD vectorization + parallel chunks

2. **Memory Allocation Overhead**  
   - Current: Dynamic ArrayList growth
   - Needed: Pre-allocated fixed-size buffers

3. **Lack of SIMD Optimizations**
   - Current: Scalar character processing
   - Needed: 16-64 byte vector processing

## Issue 4: Token System Complexity

**Problem**: The current token system is over-engineered for basic minification.

```zig
pub const Token = struct {
    token_type: TokenType,
    start: usize,
    end: usize,
    line: usize,        // Unnecessary for minification
    column: usize,      // Unnecessary for minification  
    value: ?[]const u8, // Redundant with start/end
    error_message: ?[]const u8, // Heavy for hot path
};
```

**Impact**:
- Excessive memory usage (40+ bytes per token)
- Cache misses on token stream iteration
- Unnecessary complexity for simple transformations

**Solution Path**:
```zig
// Lightweight token for high-performance paths
pub const FastToken = packed struct {
    type_and_flags: u8,  // TokenType + flags in single byte
    start: u24,          // 16MB max input size
    length: u16,         // 64KB max token length
}; // Total: 8 bytes vs 40+ bytes
```

## Performance Optimization Roadmap

### Phase 1: SIMD Foundation (Weeks 1-2)
**Target**: 500+ MB/s (4x improvement)

1. **Fix SIMD Detection**
   ```zig
   // Implement compile-time CPU feature detection
   const simd_level = comptime detectSimdLevel();
   ```

2. **Implement AVX2 Whitespace Skipping**
   ```zig
   // Process 32 bytes at once
   const whitespace_mask = @as(u32, @bitCast(_mm256_cmpeq_epi8(chunk, spaces)));
   ```

3. **Vectorized Character Classification**
   ```zig
   // Classify 32 characters simultaneously  
   const structural_mask = detectStructuralChars(chunk);
   ```

### Phase 2: Parallel Processing (Weeks 3-4)
**Target**: 2,000+ MB/s (16x improvement)

1. **Chunk-Based Parallel Processing**
   ```zig
   // Split input into 1MB chunks, process in parallel
   const chunks = splitIntoChunks(input, 1024 * 1024);
   const results = try processChunksParallel(chunks, thread_pool);
   ```

2. **Lock-Free Output Merging**
   ```zig
   // Pre-allocate output segments, merge without locks
   const output_segments = try allocateOutputSegments(chunks.len);
   ```

### Phase 3: Advanced SIMD (Weeks 5-6)  
**Target**: 5,000+ MB/s (41x improvement)

1. **AVX-512 Implementation**
   ```zig
   // Process 64 bytes per instruction
   const chunk = _mm512_loadu_si512(input_ptr);
   const mask = _mm512_cmpeq_epi8_mask(chunk, whitespace_vector);
   ```

2. **Hardware-Specific Optimization**
   ```zig
   // Detect and optimize for specific CPU architectures
   const cpu_model = detectCpuModel();
   const optimizer = getOptimizerForCpu(cpu_model);
   ```

### Phase 4: Memory Optimization (Weeks 7-8)
**Target**: 10,000+ MB/s (82x improvement)

1. **Zero-Copy Architecture**
   ```zig
   // Never copy input data, only track positions
   const output = buildOutputFromOffsets(input, valid_char_positions);
   ```

2. **Cache-Friendly Data Structures** 
   ```zig
   // Align data structures to cache lines
   const ChunkMetadata = extern struct {
       start: u32 align(64),
       length: u32,
       output_size: u32,
       padding: [52]u8, // Total 64 bytes = 1 cache line
   };
   ```

## Integration Strategy

### Immediate Actions (This Week)

1. **Fix Comptime Issues**
   - Replace function pointers with enums
   - Enable runtime transformation pipeline

2. **Basic SIMD Implementation**
   - Fix CPU feature detection
   - Implement AVX2 whitespace skipping

3. **Performance Testing Framework**
   - Automated benchmarking across data sizes
   - Regression detection for optimizations

### Medium-Term Goals (Next Month)

1. **Parallel Processing Framework**
   - Thread pool integration
   - Chunk-based processing pipeline

2. **Advanced SIMD Kernels**
   - AVX-512 support where available
   - ARM NEON optimization

3. **Memory Architecture Overhaul**
   - Replace ArrayList with fixed buffers
   - Implement memory pool hierarchies

## Risk Assessment

### High Risk
- **SIMD Complexity**: Hand-optimized assembly may be required
- **Platform Compatibility**: Different SIMD capabilities across systems
- **Memory Safety**: Manual SIMD operations bypass Zig safety

### Medium Risk  
- **Thread Synchronization**: Parallel processing coordination overhead
- **Cache Coherency**: Multi-core memory access patterns

### Low Risk
- **API Compatibility**: Can maintain existing v2 interface
- **Testing Coverage**: Existing test suite provides regression safety

## Success Metrics

### Performance Targets
- **Phase 1**: 500 MB/s (4x current)
- **Phase 2**: 2,000 MB/s (16x current) 
- **Phase 3**: 5,000 MB/s (41x current)
- **Phase 4**: 10,000+ MB/s (82x current)

### Quality Targets
- **Correctness**: 100% test pass rate maintained
- **Memory Safety**: Zero memory leaks or corruptions
- **Cross-Platform**: Linux, macOS, Windows support
- **Scalability**: Linear performance scaling with cores

## Conclusion

The v2.0 streaming engine foundation is solid with working minification at 121 MB/s. The path to 10+ GB/s is clear but requires:

1. **Immediate**: Fix comptime limitations and basic SIMD
2. **Short-term**: Implement parallel processing 
3. **Medium-term**: Advanced SIMD optimization
4. **Long-term**: Zero-copy memory architecture

The architectural framework supports these optimizations without breaking existing APIs, providing a clear upgrade path to world-class JSON processing performance.