# Migration Guide: Using Common Modules

This guide helps you migrate existing code to use the new common modules for improved code reuse and consistency.

## Overview of New Common Modules

### 1. Constants Module (`src/common/constants.zig`)
Centralizes all magic numbers and constants used throughout the codebase.

**Before:**
```zig
const CHUNK_SIZE = 64 * 1024;
const CACHE_LINE = 64;
const MAX_THREADS = 256;
```

**After:**
```zig
const constants = @import("common/constants.zig");

const CHUNK_SIZE = constants.Chunk.MEDIUM;
const CACHE_LINE = constants.System.CACHE_LINE_SIZE;
const MAX_THREADS = constants.ThreadPool.MAX_THREADS;
```

### 2. Benchmark Utilities (`src/common/benchmark_utils.zig`)
Provides consistent performance measurement and benchmarking.

**Before:**
```zig
const start = std.time.nanoTimestamp();
// ... work ...
const end = std.time.nanoTimestamp();
const elapsed_s = @as(f64, @floatFromInt(end - start)) / 1_000_000_000.0;
const throughput = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0) / elapsed_s;
```

**After:**
```zig
const benchmark_utils = @import("common/benchmark_utils.zig");

const result = try benchmark_utils.measurePerformance(myFunction, .{args}, bytes_processed);
std.debug.print("Throughput: {d:.2} MB/s\n", .{result.throughput_mbps});
```

### 3. Chunk Utilities (`src/common/chunk_utils.zig`)
Handles chunk size calculations and work distribution.

**Before:**
```zig
// Manual chunk size calculation with hardcoded values
var chunk_size = if (file_size < 64 * 1024) 16 * 1024 else 64 * 1024;
chunk_size = @min(chunk_size, file_size / (thread_count * 4));
```

**After:**
```zig
const chunk_utils = @import("common/chunk_utils.zig");

const recommendation = chunk_utils.calculateOptimalChunkSize(.{
    .data_size = file_size,
    .thread_count = thread_count,
    .cpu_features = cpu_features,
});
const chunk_size = recommendation.size;
```

### 4. JSON Utilities (`src/common/json_utils.zig`)
Provides common JSON validation and processing functions.

**Before:**
```zig
// Manual JSON validation with depth tracking
var depth: u32 = 0;
for (input) |c| {
    switch (c) {
        '{', '[' => depth += 1,
        '}', ']' => depth -= 1,
        // ... more manual parsing
    }
}
```

**After:**
```zig
const json_utils = @import("common/json_utils.zig");

try json_utils.validateJson(input);
```

### 5. Buffer Utilities (`src/common/buffer_utils.zig`)
Offers various buffer types for different use cases.

**Before:**
```zig
// Manual dynamic buffer implementation
const Buffer = struct {
    data: []u8,
    len: usize,
    capacity: usize,
    // ... manual growth logic
};
```

**After:**
```zig
const buffer_utils = @import("common/buffer_utils.zig");

var buffer = try buffer_utils.DynamicBuffer.init(allocator, initial_size);
defer buffer.deinit();

try buffer.append("data");
const result = buffer.slice();
```

### 6. Work Queue (`src/common/work_queue.zig`)
Provides work-stealing queue implementation for parallel processing.

**Before:**
```zig
// Manual work queue with mutex-based synchronization
const WorkQueue = struct {
    items: []WorkItem,
    mutex: std.Thread.Mutex,
    // ... manual implementation
};
```

**After:**
```zig
const work_queue = @import("common/work_queue.zig");

var scheduler = try work_queue.WorkStealingScheduler.init(allocator, .{
    .thread_count = 4,
    .steal_strategy = .work_guided,
});
defer scheduler.deinit();
```

## Migration Steps

### Step 1: Update Imports
Add imports for the common modules you need:

```zig
const constants = @import("common/constants.zig");
const benchmark_utils = @import("common/benchmark_utils.zig");
const chunk_utils = @import("common/chunk_utils.zig");
const json_utils = @import("common/json_utils.zig");
const buffer_utils = @import("common/buffer_utils.zig");
const work_queue = @import("common/work_queue.zig");
```

### Step 2: Replace Magic Numbers
Search for hardcoded values and replace with constants:

```bash
# Find common magic numbers
grep -r "64 \* 1024" src/
grep -r "256 \* 1024" src/
grep -r "cache.*64" src/
```

### Step 3: Update Benchmark Code
Replace manual timing code with benchmark utilities:

```zig
// Create a benchmark suite
var suite = benchmark_utils.BenchmarkSuite.init(allocator, "My Benchmarks");
defer suite.deinit();

// Add benchmarks
try suite.addBenchmark("Test 1", myFunction, .{args}, bytes);

// Print results
suite.printResults();
```

### Step 4: Use Common Patterns
Replace custom implementations with common utilities:

- Buffer management → `buffer_utils.DynamicBuffer`
- Ring buffers → `buffer_utils.RingBuffer`
- JSON building → `buffer_utils.JsonBuilder`
- Work distribution → `chunk_utils.distributeWork`
- CPU detection → `platform/simd_detector.zig`

### Step 5: Update Build Configuration
Use the common build helpers in `build/common.zig`:

```zig
const common = @import("build/common.zig");

const config = common.BuildConfig.fromBuild(b);
const exe = common.createExecutable(b, "myapp", "src/main.zig", config);
```

## Benefits After Migration

1. **Consistency**: All modules use the same constants and patterns
2. **Maintainability**: Single source of truth for common functionality
3. **Performance**: Optimized implementations in one place
4. **Testing**: Easier to test with common fixtures and helpers
5. **Documentation**: Self-documenting through well-named constants

## Common Pitfalls to Avoid

1. **Don't mix old and new patterns** - Fully migrate each module
2. **Update tests** - Ensure tests use the new utilities
3. **Check alignment** - Some constants have alignment requirements
4. **Benchmark after migration** - Ensure performance is maintained

## Example: Full Module Migration

See `examples/migration_example.zig` for a complete example of migrating a module to use all the new common utilities.

## Need Help?

- Check the source files for detailed documentation
- Run tests to ensure compatibility
- Use the migration example as a reference