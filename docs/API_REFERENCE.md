# zmin API Reference

Complete API documentation for the zmin high-performance JSON minifier.

## Table of Contents
1. [Simple API](#simple-api)
2. [Advanced API](#advanced-api) 
3. [Streaming API](#streaming-api)
4. [Utility Functions](#utility-functions)
5. [Error Handling](#error-handling)
6. [Performance Tuning](#performance-tuning)

## Simple API

The simple API covers 90% of use cases with minimal configuration.

### Functions

#### `minify`
```zig
pub fn minify(allocator: std.mem.Allocator, input: []const u8) ![]u8
```

Minifies a JSON string with automatic optimization.

**Parameters:**
- `allocator`: Memory allocator for the output buffer
- `input`: JSON string to minify

**Returns:**
- Minified JSON string (caller owns memory)

**Errors:**
- `InvalidJson`: Input is not valid JSON
- `OutOfMemory`: Memory allocation failed

**Example:**
```zig
const std = @import("std");
const zmin = @import("zmin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const input = "{ \"name\" : \"John\" , \"age\" : 30 }";
    const output = try zmin.minify(gpa.allocator(), input);
    defer gpa.allocator().free(output);
    
    std.debug.print("{s}\n", .{output}); // {"name":"John","age":30}
}
```

#### `minifyToWriter`
```zig
pub fn minifyToWriter(input: []const u8, writer: anytype) !void
```

Minifies JSON directly to a writer without allocation.

**Parameters:**
- `input`: JSON string to minify
- `writer`: Any type implementing the Writer interface

**Errors:**
- `InvalidJson`: Input is not valid JSON
- Writer errors propagated from the writer

**Example:**
```zig
const stdout = std.io.getStdOut().writer();
try zmin.minifyToWriter(json_input, stdout);
```

#### `minifyFile`
```zig
pub fn minifyFile(allocator: std.mem.Allocator, path: []const u8) ![]u8
```

Reads and minifies a JSON file.

**Parameters:**
- `allocator`: Memory allocator
- `path`: File path to read

**Returns:**
- Minified JSON string

**Example:**
```zig
const minified = try zmin.minifyFile(allocator, "data.json");
defer allocator.free(minified);
```

## Advanced API

The advanced API provides fine-grained control over the minification process.

### Types

#### `Config`
```zig
pub const Config = struct {
    optimization_level: OptimizationLevel = .automatic,
    validate_input: bool = true,
    preserve_precision: bool = true,
    memory_strategy: MemoryStrategy = .adaptive,
    chunk_size: usize = 64 * 1024,
    parallel_threshold: usize = 1024 * 1024,
};
```

#### `OptimizationLevel`
```zig
pub const OptimizationLevel = enum {
    none,       // No optimization, fastest compilation
    basic,      // Basic SIMD optimizations
    aggressive, // Full SIMD + parallel processing
    extreme,    // All optimizations including experimental
    automatic,  // Auto-select based on input and hardware
};
```

#### `MemoryStrategy`
```zig
pub const MemoryStrategy = enum {
    standard,   // Standard allocator
    pooled,     // Memory pools for small allocations
    numa_aware, // NUMA-aware allocation
    adaptive,   // Auto-select based on system
};
```

### Advanced Minifier

#### `AdvancedMinifier.init`
```zig
pub fn init(allocator: std.mem.Allocator, config: Config) !*AdvancedMinifier
```

Creates an advanced minifier with custom configuration.

**Example:**
```zig
const config = Config{
    .optimization_level = .aggressive,
    .memory_strategy = .pooled,
    .chunk_size = 128 * 1024,
};

var minifier = try AdvancedMinifier.init(allocator, config);
defer minifier.deinit();
```

#### `AdvancedMinifier.minify`
```zig
pub fn minify(self: *AdvancedMinifier, input: []const u8) ![]u8
```

Minifies JSON with configured settings.

#### `AdvancedMinifier.minifyWithStats`
```zig
pub fn minifyWithStats(self: *AdvancedMinifier, input: []const u8) !MinifyResult

pub const MinifyResult = struct {
    output: []u8,
    stats: PerformanceStats,
};

pub const PerformanceStats = struct {
    input_size: usize,
    output_size: usize,
    duration_ns: u64,
    throughput_gbps: f64,
    strategy_used: ProcessingStrategy,
};
```

Minifies and returns performance statistics.

**Example:**
```zig
const result = try minifier.minifyWithStats(input);
defer allocator.free(result.output);

std.debug.print("Throughput: {d:.2} GB/s\n", .{result.stats.throughput_gbps});
```

## Streaming API

For processing large files or continuous streams.

### Types

#### `StreamConfig`
```zig
pub const StreamConfig = struct {
    buffer_size: usize = 64 * 1024,
    validate_chunks: bool = true,
    on_error: ErrorStrategy = .stop,
};

pub const ErrorStrategy = enum {
    stop,     // Stop on first error
    skip,     // Skip invalid chunks
    report,   // Report errors but continue
};
```

### StreamingMinifier

#### `StreamingMinifier.init`
```zig
pub fn init(writer: anytype, config: StreamConfig) !StreamingMinifier
```

Creates a streaming minifier.

#### `StreamingMinifier.feedChunk`
```zig
pub fn feedChunk(self: *StreamingMinifier, chunk: []const u8) !void
```

Processes a chunk of JSON data.

#### `StreamingMinifier.finish`
```zig
pub fn finish(self: *StreamingMinifier) !void
```

Finalizes processing and flushes remaining data.

**Example:**
```zig
var file = try std.fs.cwd().openFile("large.json", .{});
defer file.close();

var buffered = std.io.bufferedWriter(std.io.getStdOut().writer());
var minifier = try StreamingMinifier.init(buffered.writer(), .{});

var buffer: [8192]u8 = undefined;
while (true) {
    const bytes_read = try file.read(&buffer);
    if (bytes_read == 0) break;
    
    try minifier.feedChunk(buffer[0..bytes_read]);
}

try minifier.finish();
try buffered.flush();
```

## Utility Functions

### Validation

#### `validateJSON`
```zig
pub fn validateJSON(input: []const u8) !void
```

Validates JSON without minification.

**Errors:**
- `InvalidJson`: With position and error details

#### `validateJSONVerbose`
```zig
pub fn validateJSONVerbose(input: []const u8) ValidationResult

pub const ValidationResult = struct {
    is_valid: bool,
    error_position: ?usize = null,
    error_message: ?[]const u8 = null,
    line: ?usize = null,
    column: ?usize = null,
};
```

Returns detailed validation information.

### Size Estimation

#### `estimateMinifiedSize`
```zig
pub fn estimateMinifiedSize(input: []const u8) usize
```

Estimates output size for memory allocation.

### Semantic Comparison

#### `semanticEquals`
```zig
pub fn semanticEquals(a: []const u8, b: []const u8) bool
```

Checks if two JSON strings are semantically equivalent.

**Example:**
```zig
const a = "{ \"a\": 1, \"b\": 2 }";
const b = "{\"b\":2,\"a\":1}";
assert(zmin.semanticEquals(a, b)); // true - same content
```

## Error Handling

### Error Types

```zig
pub const MinifierError = error{
    InvalidJson,
    UnexpectedEndOfInput,
    InvalidEscapeSequence,
    InvalidNumber,
    InvalidUnicodeEscape,
    NestingTooDeep,
    BufferTooSmall,
    StreamingError,
};
```

### Error Context

Get detailed error information:

```zig
const result = zmin.minify(allocator, input) catch |err| {
    const ctx = zmin.getErrorContext();
    std.debug.print("Error at position {}: {s}\n", .{
        ctx.position,
        ctx.message,
    });
    return err;
};
```

## Performance Tuning

### Hardware Detection

```zig
const caps = zmin.detectHardwareCapabilities();

pub const HardwareCapabilities = struct {
    arch_type: ArchType,
    has_avx2: bool,
    has_avx512: bool,
    has_neon: bool,
    cpu_count: u32,
    cache_line_size: u16,
    // ... more fields
};
```

### Performance Configuration

```zig
// For maximum throughput
const config = Config{
    .optimization_level = .extreme,
    .memory_strategy = .numa_aware,
    .chunk_size = 256 * 1024,
    .parallel_threshold = 512 * 1024,
};

// For low latency
const config = Config{
    .optimization_level = .basic,
    .memory_strategy = .standard,
    .chunk_size = 8 * 1024,
    .validate_input = false, // Skip validation for speed
};

// For embedded systems
const config = Config{
    .optimization_level = .none,
    .memory_strategy = .standard,
    .chunk_size = 1024,
};
```

### Benchmarking

```zig
const benchmark_result = try zmin.benchmark(allocator, test_data, .{
    .iterations = 1000,
    .warmup_iterations = 100,
});

std.debug.print("Average: {d:.2} GB/s\n", .{benchmark_result.avg_throughput});
std.debug.print("Peak: {d:.2} GB/s\n", .{benchmark_result.peak_throughput});
```

## Thread Safety

The simple API functions are thread-safe when using different allocators. The Advanced and Streaming APIs maintain per-instance state and should not be shared between threads without synchronization.

For parallel processing:
```zig
var pool = try zmin.ThreadPool.init(allocator, .{
    .thread_count = 4,
});
defer pool.deinit();

const results = try pool.minifyBatch(files);
```

## Examples

### Web Server Integration
```zig
fn handleRequest(request: Request, response: Response) !void {
    const json = try request.body();
    
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    
    const minified = try zmin.minify(arena.allocator(), json);
    
    response.headers.set("Content-Type", "application/json");
    try response.writer().writeAll(minified);
}
```

### CLI Tool
```zig
pub fn main() !void {
    var args = std.process.args();
    _ = args.next(); // skip program name
    
    const input_file = args.next() orelse {
        std.debug.print("Usage: zmin <input.json> [output.json]\n", .{});
        return;
    };
    
    const output_file = args.next();
    
    const minified = try zmin.minifyFile(allocator, input_file);
    defer allocator.free(minified);
    
    if (output_file) |path| {
        try std.fs.cwd().writeFile(path, minified);
    } else {
        try std.io.getStdOut().writeAll(minified);
    }
}
```

### Batch Processing
```zig
const files = try findJSONFiles("data/");
var results = std.ArrayList([]u8).init(allocator);

for (files) |file| {
    const minified = zmin.minifyFile(allocator, file) catch |err| {
        std.log.err("Failed to minify {s}: {}", .{ file, err });
        continue;
    };
    try results.append(minified);
}
```

## Migration Guide

### From v1.x to v2.x
```zig
// Old API
const result = try zmin.minifyJSON(input);

// New API  
const result = try zmin.minify(allocator, input);
defer allocator.free(result);
```

## Performance Characteristics

| Input Size | Expected Throughput | Memory Usage |
|------------|-------------------|--------------|
| < 1 KB     | 1-2 GB/s         | O(n)         |
| 1-100 KB   | 2-3 GB/s         | O(n)         |
| 100KB-1MB  | 3-4 GB/s         | O(n)         |
| 1-10 MB    | 4-5 GB/s         | O(n)         |
| > 10 MB    | 5+ GB/s          | O(n/p) with parallel |

Where n = input size, p = parallelism level