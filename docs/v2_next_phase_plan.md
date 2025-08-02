# zmin v2.0 - Next Phase Implementation Plan

## Phase 1: SIMD Foundation Implementation
**Timeline**: Weeks 1-2 | **Target**: 500+ MB/s (4x improvement)

### Week 1: Fix Architectural Issues

#### Day 1-2: Resolve Comptime Limitations
```zig
// File: src/v2/transformations/runtime_pipeline.zig
pub const RuntimeTransformation = struct {
    type: TransformationType,
    config: TransformationConfig,
    enabled: bool = true,
    priority: u32 = 0,
};

pub const TransformationType = enum {
    minify_whitespace,
    minify_aggressive, 
    filter_fields,
    validate_schema,
    convert_format,
};

// Replace function pointers with runtime dispatch
pub fn executeTransformation(
    transformation: RuntimeTransformation,
    input: []const u8,
    output: *std.ArrayList(u8),
) !void {
    switch (transformation.type) {
        .minify_whitespace => try executeMinifyWhitespace(input, output),
        .minify_aggressive => try executeMinifyAggressive(input, output),
        // ... other transformations
    }
}
```

#### Day 3-4: Fix SIMD Detection
```zig
// File: src/v2/simd/cpu_detection.zig
pub const SimdCapabilities = struct {
    has_sse2: bool,
    has_avx2: bool, 
    has_avx512: bool,
    has_neon: bool, // ARM
};

pub fn detectSimdCapabilities() SimdCapabilities {
    const builtin = @import("builtin");
    
    return SimdCapabilities{
        .has_sse2 = comptime builtin.cpu.features.isEnabled(.sse2),
        .has_avx2 = comptime builtin.cpu.features.isEnabled(.avx2),
        .has_avx512 = comptime builtin.cpu.features.isEnabled(.avx512f),
        .has_neon = comptime builtin.cpu.arch == .aarch64,
    };
}
```

#### Day 5: Create New v2 Engine
```zig
// File: src/v2/runtime_engine.zig
pub const RuntimeEngine = struct {
    allocator: Allocator,
    simd_caps: SimdCapabilities,
    transformations: std.ArrayList(RuntimeTransformation),
    
    pub fn init(allocator: Allocator) !RuntimeEngine {
        return RuntimeEngine{
            .allocator = allocator,
            .simd_caps = detectSimdCapabilities(),
            .transformations = std.ArrayList(RuntimeTransformation).init(allocator),
        };
    }
    
    pub fn minify(self: *RuntimeEngine, input: []const u8) ![]u8 {
        // Choose optimal minification path based on SIMD capabilities
        if (self.simd_caps.has_avx2) {
            return self.minifyAvx2(input);
        } else if (self.simd_caps.has_sse2) {
            return self.minifysse2(input);
        } else {
            return self.minifyScalar(input);
        }
    }
};
```

### Week 2: Basic SIMD Implementation

#### Day 1-3: AVX2 Whitespace Detection
```zig
// File: src/v2/simd/avx2_minifier.zig
const std = @import("std");

pub fn minifyAvx2(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if (input.len == 0) return try allocator.alloc(u8, 0);
    
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    const chunk_size = 32; // Process 32 bytes at a time with AVX2
    var i: usize = 0;
    var in_string = false;
    
    // Process aligned chunks
    while (i + chunk_size <= input.len) {
        if (in_string) {
            // Inside string - find end quote and copy verbatim
            const string_end = findStringEndAvx2(input[i..], chunk_size);
            try output.appendSlice(input[i..i + string_end]);
            i += string_end;
            if (input[i-1] == '"') in_string = false;
        } else {
            // Outside string - vectorized whitespace removal
            const non_whitespace_mask = detectNonWhitespaceAvx2(input[i..i + chunk_size]);
            i += try appendNonWhitespaceChars(&output, input[i..i + chunk_size], non_whitespace_mask, &in_string);
        }
    }
    
    // Handle remaining bytes with scalar code
    while (i < input.len) {
        const char = input[i];
        if (in_string or (char != ' ' and char != '\t' and char != '\n' and char != '\r')) {
            try output.append(char);
            if (char == '"' and (i == 0 or input[i-1] != '\\')) {
                in_string = !in_string;
            }
        }
        i += 1;
    }
    
    return output.toOwnedSlice();
}

// Placeholder for actual AVX2 intrinsics
fn detectNonWhitespaceAvx2(chunk: []const u8) u32 {
    // This would use actual AVX2 instructions in production
    var mask: u32 = 0;
    for (chunk, 0..) |char, idx| {
        if (char != ' ' and char != '\t' and char != '\n' and char != '\r') {
            mask |= (@as(u32, 1) << @intCast(idx));
        }
    }
    return mask;
}
```

#### Day 4-5: Performance Testing Framework
```zig
// File: src/v2/benchmarks/simd_benchmarks.zig
pub fn benchmarkSimdMinification(allocator: std.mem.Allocator) !void {
    const test_sizes = [_]usize{ 1024, 10240, 102400, 1024000 };
    const iterations = 1000;
    
    for (test_sizes) |size| {
        // Generate test data
        const test_data = try generateTestJson(allocator, size);
        defer allocator.free(test_data);
        
        // Benchmark scalar version
        const scalar_time = try benchmarkFunction(minifyScalar, allocator, test_data, iterations);
        
        // Benchmark SIMD versions if available
        const caps = detectSimdCapabilities();
        
        if (caps.has_avx2) {
            const avx2_time = try benchmarkFunction(minifyAvx2, allocator, test_data, iterations);
            const speedup = @as(f64, @floatFromInt(scalar_time)) / @as(f64, @floatFromInt(avx2_time));
            std.debug.print("AVX2 speedup for {}KB: {:.2}x\n", .{ size / 1024, speedup });
        }
    }
}
```

## Phase 2: Parallel Processing Framework 
**Timeline**: Weeks 3-4 | **Target**: 2,000+ MB/s (16x improvement)

### Week 3: Chunk-Based Parallel Architecture

#### Day 1-2: Parallel Chunk Processor
```zig
// File: src/v2/parallel/chunk_processor.zig
pub const ChunkProcessor = struct {
    thread_pool: std.Thread.Pool,
    chunk_size: usize,
    
    pub fn init(allocator: std.mem.Allocator, thread_count: u32) !ChunkProcessor {
        const pool = try std.Thread.Pool.init(.{
            .allocator = allocator,
            .n_jobs = thread_count,
        });
        
        return ChunkProcessor{
            .thread_pool = pool,
            .chunk_size = 256 * 1024, // 256KB chunks
        };
    }
    
    pub fn minifyParallel(self: *ChunkProcessor, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        const chunk_count = (input.len + self.chunk_size - 1) / self.chunk_size;
        
        // Create chunk descriptors
        var chunks = try allocator.alloc(ChunkDescriptor, chunk_count);
        defer allocator.free(chunks);
        
        // Initialize chunks
        for (chunks, 0..) |*chunk, i| {
            const start = i * self.chunk_size;
            const end = @min(start + self.chunk_size, input.len);
            chunk.* = ChunkDescriptor{
                .input = input[start..end],
                .output = std.ArrayList(u8).init(allocator),
                .start_offset = start,
            };
        }
        
        // Process chunks in parallel
        try self.processChunksParallel(chunks);
        
        // Merge results
        return try mergeChunkOutputs(allocator, chunks);
    }
};
```

#### Day 3-4: Lock-Free Output Merging
```zig
// File: src/v2/parallel/lock_free_merger.zig
pub fn mergeChunkOutputs(allocator: std.mem.Allocator, chunks: []ChunkDescriptor) ![]u8 {
    // Calculate total output size
    var total_size: usize = 0;
    for (chunks) |chunk| {
        total_size += chunk.output.items.len;
    }
    
    // Pre-allocate output buffer
    var output = try allocator.alloc(u8, total_size);
    
    // Merge without locks (chunks processed in order)
    var offset: usize = 0;
    for (chunks) |chunk| {
        @memcpy(output[offset..offset + chunk.output.items.len], chunk.output.items);
        offset += chunk.output.items.len;
        chunk.output.deinit(); // Cleanup
    }
    
    return output;
}
```

### Week 4: Advanced Parallel Optimization

#### Day 1-3: Work-Stealing Algorithm
```zig
// File: src/v2/parallel/work_stealing.zig
pub const WorkStealingProcessor = struct {
    workers: []Worker,
    task_queues: []std.atomic.Queue(Task),
    
    pub fn processParallel(self: *WorkStealingProcessor, input: []const u8) ![]u8 {
        // Divide work into more tasks than workers
        const task_count = self.workers.len * 4;
        const tasks = try self.createTasks(input, task_count);
        
        // Distribute initial tasks
        for (tasks, 0..) |task, i| {
            const queue_idx = i % self.task_queues.len;
            try self.task_queues[queue_idx].put(task);
        }
        
        // Start workers with work-stealing
        try self.startWorkersWithStealing();
        
        return self.collectResults();
    }
};
```

## Phase 3: Advanced SIMD Kernels
**Timeline**: Weeks 5-6 | **Target**: 5,000+ MB/s (41x improvement)

### Implementation Strategy

#### AVX-512 String Processing
```zig
// File: src/v2/simd/avx512_kernels.zig
pub fn processStringAvx512(input: []const u8, output: *std.ArrayList(u8)) !void {
    const vector_size = 64; // AVX-512 processes 64 bytes
    var i: usize = 0;
    
    while (i + vector_size <= input.len) {
        // Load 64 bytes
        const chunk = @as(@Vector(64, u8), input[i..i + vector_size][0..64].*);
        
        // Create comparison vectors
        const spaces = @splat(@as(u8, ' '));
        const tabs = @splat(@as(u8, '\t'));
        const newlines = @splat(@as(u8, '\n'));
        const returns = @splat(@as(u8, '\r'));
        
        // Generate whitespace mask
        const space_mask = chunk == spaces;
        const tab_mask = chunk == tabs;
        const newline_mask = chunk == newlines;
        const return_mask = chunk == returns;
        
        const whitespace_mask = space_mask | tab_mask | newline_mask | return_mask;
        const keep_mask = ~whitespace_mask;
        
        // Compress and store non-whitespace characters
        try compressAndStore(chunk, keep_mask, output);
        
        i += vector_size;
    }
}
```

## Testing Strategy

### Automated Performance Regression Testing
```zig
// File: tests/v2/performance_regression.zig
test "performance regression - never slower than baseline" {
    const baseline_performance = 121; // MB/s from current implementation
    
    const test_cases = [_]TestCase{
        .{ .name = "small", .size = 1024 },
        .{ .name = "medium", .size = 100 * 1024 },
        .{ .name = "large", .size = 10 * 1024 * 1024 },
    };
    
    for (test_cases) |test_case| {
        const performance = try measurePerformance(test_case.size);
        
        // Must be at least as fast as baseline
        try std.testing.expect(performance >= baseline_performance);
        
        // Log improvement
        const improvement = performance / baseline_performance;
        std.debug.print("{s}: {:.1}x improvement ({:.1} MB/s)\n", .{
            test_case.name, improvement, performance
        });
    }
}
```

### Correctness Validation
```zig
// File: tests/v2/correctness_validation.zig
test "SIMD results identical to scalar results" {
    const test_inputs = try loadTestJsonFiles();
    
    for (test_inputs) |input| {
        const scalar_result = try minifyScalar(std.testing.allocator, input);
        defer std.testing.allocator.free(scalar_result);
        
        if (detectSimdCapabilities().has_avx2) {
            const simd_result = try minifyAvx2(std.testing.allocator, input);
            defer std.testing.allocator.free(simd_result);
            
            try std.testing.expectEqualStrings(scalar_result, simd_result);
        }
    }
}
```

## Success Criteria

### Phase 1 Complete When:
- [ ] Runtime transformation pipeline working (no comptime errors)
- [ ] SIMD detection functional across platforms
- [ ] AVX2 implementation achieving 4x speedup on supported hardware
- [ ] All existing tests pass with new implementation

### Phase 2 Complete When:
- [ ] Parallel processing framework operational
- [ ] Linear scaling with CPU cores (up to 8 cores)
- [ ] 16x speedup achieved on multi-core systems
- [ ] Memory usage remains bounded during parallel processing

### Phase 3 Complete When:
- [ ] AVX-512 kernels implemented and tested
- [ ] 41x speedup achieved on compatible hardware
- [ ] Cross-platform SIMD abstraction layer complete
- [ ] Performance target of 5+ GB/s reached

This implementation plan provides a clear, actionable path from the current 121 MB/s baseline to the 10+ GB/s target, with measurable milestones and comprehensive testing at each phase.