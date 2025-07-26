# Mode Testing Plan

## Test Coverage Strategy

### 1. Mode Consistency Tests
Ensure all modes produce bit-identical output:

```zig
// tests/modes/consistency_tests.zig
test "all modes produce identical output" {
    const TestCase = struct {
        name: []const u8,
        input: []const u8,
        expected: []const u8,
    };
    
    const test_cases = [_]TestCase{
        .{ .name = "empty", .input = "", .expected = "" },
        .{ .name = "null", .input = "null", .expected = "null" },
        .{ .name = "whitespace", .input = "  {  }  ", .expected = "{}" },
        .{ .name = "nested", .input = 
            \\{
            \\  "a": {
            \\    "b": [1, 2, 3]
            \\  }
            \\}
        , .expected = \\{"a":{"b":[1,2,3]}} },
        // ... 50+ more cases
    };
    
    for (test_cases) |tc| {
        const eco = try minifyMode(.eco, tc.input);
        const sport = try minifyMode(.sport, tc.input);
        const turbo = try minifyMode(.turbo, tc.input);
        
        try testing.expectEqualStrings(tc.expected, eco);
        try testing.expectEqualStrings(tc.expected, sport);
        try testing.expectEqualStrings(tc.expected, turbo);
    }
}
```

### 2. Performance Benchmarks

```zig
// tests/modes/performance_tests.zig
const PerformanceTarget = struct {
    mode: ProcessingMode,
    min_throughput_mbps: f64,
    max_memory_bytes: usize,
    tolerance_percent: f64 = 10.0,
};

const targets = [_]PerformanceTarget{
    .{ .mode = .eco, .min_throughput_mbps = 90, .max_memory_bytes = 64 * 1024 },
    .{ .mode = .sport, .min_throughput_mbps = 400, .max_memory_bytes = 16 * 1024 * 1024 },
    .{ .mode = .turbo, .min_throughput_mbps = 2000, .max_memory_bytes = std.math.maxInt(usize) },
};

test "mode performance targets" {
    for (targets) |target| {
        const result = try benchmarkMode(target.mode);
        
        // Verify throughput
        const min_acceptable = target.min_throughput_mbps * (1 - target.tolerance_percent / 100);
        try testing.expect(result.throughput_mbps >= min_acceptable);
        
        // Verify memory
        try testing.expect(result.peak_memory <= target.max_memory_bytes);
    }
}
```

### 3. Memory Scaling Tests

```zig
// tests/modes/memory_tests.zig
test "ECO mode constant memory" {
    const sizes = [_]usize{ 1_KB, 1_MB, 10_MB, 100_MB, 1_GB };
    var memories: [sizes.len]usize = undefined;
    
    for (sizes, 0..) |size, i| {
        const input = try generateJson(size);
        memories[i] = try measurePeakMemory(.eco, input);
    }
    
    // All measurements should be ~64KB
    for (memories) |mem| {
        try testing.expectApproxEqRel(@as(f64, 64 * 1024), @as(f64, mem), 0.1);
    }
}

test "SPORT mode sqrt memory scaling" {
    const TestPoint = struct { size: usize, expected_memory: usize };
    const points = [_]TestPoint{
        .{ .size = 1_MB, .expected_memory = 1_KB },
        .{ .size = 100_MB, .expected_memory = 10_MB },
        .{ .size = 1_GB, .expected_memory = 16_MB }, // capped at 16MB
    };
    
    for (points) |point| {
        const input = try generateJson(point.size);
        const memory = try measurePeakMemory(.sport, input);
        try testing.expectApproxEqRel(
            @as(f64, point.expected_memory), 
            @as(f64, memory), 
            0.2
        );
    }
}
```

### 4. SIMD Validation Tests

```zig
// tests/modes/simd_tests.zig
test "SIMD correctness" {
    // Test SIMD against scalar implementation
    const test_patterns = [_][]const u8{
        "a" ** 32, // Aligned pattern
        "a" ** 31, // Unaligned pattern
        "\\" ** 32, // Escape characters
        "\"" ** 32, // Quote characters
        "🚀" ** 8, // Unicode characters
    };
    
    for (test_patterns) |pattern| {
        const json = try std.fmt.allocPrint(allocator, "[\"{s}\"]", .{pattern});
        
        const scalar_result = try minifyScalar(json);
        const simd_result = try minifySIMD(json);
        
        try testing.expectEqualStrings(scalar_result, simd_result);
    }
}

test "SIMD platform fallback" {
    // Force disable SIMD
    const saved_features = builtin.cpu.features;
    builtin.cpu.features = .{};
    defer builtin.cpu.features = saved_features;
    
    // Should still work
    const result = try minifyMode(.turbo, test_json);
    try testing.expectEqualStrings(expected, result);
}
```

### 5. Streaming Tests

```zig
// tests/modes/streaming_tests.zig
test "streaming mode chunks" {
    const ChunkTest = struct {
        chunks: []const []const u8,
        expected: []const u8,
    };
    
    const tests = [_]ChunkTest{
        .{
            .chunks = &[_][]const u8{ "{", "\"a\"", ":", "1", "}" },
            .expected = "{\"a\":1}",
        },
        .{
            .chunks = &[_][]const u8{ "[", "1,", "2,", "3", "]" },
            .expected = "[1,2,3]",
        },
        .{
            // String split across chunks
            .chunks = &[_][]const u8{ "{\"na", "me\":\"va", "lue\"}" },
            .expected = "{\"name\":\"value\"}",
        },
    };
    
    for (tests) |t| {
        var sport_result = std.ArrayList(u8).init(allocator);
        var sport_minifier = SportMinifier.init(allocator);
        
        for (t.chunks) |chunk| {
            try sport_minifier.processChunk(chunk, &sport_result);
        }
        
        try testing.expectEqualStrings(t.expected, sport_result.items);
    }
}
```

### 6. Error Handling Tests

```zig
// tests/modes/error_tests.zig
test "mode error handling" {
    const invalid_inputs = [_][]const u8{
        "{", // Incomplete
        "}", // Unmatched
        "{\"a\":", // Incomplete value
        "[1,2,", // Incomplete array
    };
    
    for (invalid_inputs) |input| {
        // ECO mode might be lenient
        _ = minifyMode(.eco, input) catch |err| {
            try testing.expect(err == error.InvalidJson);
        };
        
        // TURBO mode with validation should catch errors
        const result = minifyMode(.turbo, input);
        try testing.expectError(error.InvalidJson, result);
    }
}
```

### 7. Integration Tests

```zig
// tests/modes/integration_tests.zig
test "real world files" {
    const files = [_][]const u8{
        "package.json",
        "tsconfig.json",
        "swagger.json",
        "geojson-sample.json",
    };
    
    for (files) |file| {
        const content = try std.fs.cwd().readFileAlloc(allocator, file, 10_MB);
        
        // Test all modes
        const eco = try minifyMode(.eco, content);
        const sport = try minifyMode(.sport, content);
        const turbo = try minifyMode(.turbo, content);
        
        // Verify identical output
        try testing.expectEqualStrings(eco, sport);
        try testing.expectEqualStrings(eco, turbo);
        
        // Verify valid JSON
        _ = try std.json.parseFromSlice(std.json.Value, allocator, eco, .{});
    }
}
```

## Test Execution Strategy

### Continuous Integration

```yaml
# .github/workflows/mode_tests.yml
name: Mode Tests

on: [push, pull_request]

jobs:
  test-matrix:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        mode: [eco, sport, turbo]
        zig: [0.11.0, 0.12.0, master]
    
    steps:
      - name: Run ${{ matrix.mode }} tests
        run: |
          zig build test -Dtest-filter=mode_${{ matrix.mode }}
          zig build benchmark -Dmode=${{ matrix.mode }}
```

### Local Testing

```bash
# Run all mode tests
zig build test:modes

# Run specific mode tests
zig build test:eco
zig build test:sport  
zig build test:turbo

# Run performance benchmarks
zig build benchmark:modes

# Run memory profiling
zig build profile:memory
```

## Coverage Requirements

| Component | Target | Priority |
|-----------|--------|----------|
| Mode Selection | 100% | Critical |
| ECO Mode | 100% | Critical |
| SPORT Mode | 95% | High |
| TURBO Mode | 95% | High |
| SIMD Code | 90% | High |
| Error Paths | 90% | Medium |
| Platform Fallbacks | 100% | Critical |

## Test Data Sets

### Standard Test Files
- `minimal.json` - Single value
- `simple.json` - Basic object
- `nested.json` - Deep nesting
- `array.json` - Large arrays
- `strings.json` - String edge cases
- `numbers.json` - Numeric formats
- `unicode.json` - UTF-8 stress test
- `mixed.json` - Real-world mix

### Performance Test Files
- `1mb.json` - Small file
- `10mb.json` - Medium file
- `100mb.json` - Large file
- `1gb.json` - Huge file

### Stress Test Files
- `deep_nesting.json` - 1000 levels
- `wide_array.json` - 1M elements
- `huge_string.json` - 100MB string
- `many_objects.json` - 1M objects