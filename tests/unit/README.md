# Dev Tools Unit Tests

This directory contains comprehensive unit tests for all zmin development tools.

## Test Organization

### Test Modules

- **`dev_tools_tests.zig`** - Common error handling and shared infrastructure tests
- **`dev_server_tests.zig`** - Development server functionality tests  
- **`debugger_tests.zig`** - Debugger tool functionality tests
- **`plugin_registry_tests.zig`** - Plugin registry management tests
- **`dev_tools_test_suite.zig`** - Comprehensive test suite runner with integration tests

### Test Coverage

#### Common Error Handling (`dev_tools_tests.zig`)
- ✅ ErrorReporter initialization and configuration
- ✅ Error context creation and formatting
- ✅ FileOps wrapper functionality
- ✅ ProcessOps wrapper functionality
- ✅ DevToolError type validation

#### Dev Server (`dev_server_tests.zig`)
- ✅ HTTP request parsing and validation
- ✅ JSON response formatting
- ✅ Error handling integration
- ✅ File operations (embedded files, static assets)
- ✅ System information detection
- ✅ Mock connection testing

#### Debugger (`debugger_tests.zig`)
- ✅ Command line argument parsing
- ✅ Performance profiling functionality
- ✅ Memory tracking and leak detection
- ✅ System information gathering
- ✅ Benchmark data generation and statistics
- ✅ File operations and log management

#### Plugin Registry (`plugin_registry_tests.zig`)
- ✅ Command parsing and validation
- ✅ Plugin discovery and loading simulation
- ✅ Plugin testing and benchmarking
- ✅ Error handling for plugin operations
- ✅ Mock plugin loader implementation

#### Integration Tests (`dev_tools_test_suite.zig`)
- ✅ Cross-tool interaction testing
- ✅ Error handling consistency across tools
- ✅ Performance benchmarking
- ✅ Memory usage validation
- ✅ End-to-end workflow testing

## Running Tests

### Individual Test Modules

Run individual test modules:

```bash
# Common error handling tests
zig run tests/unit/dev_tools_tests.zig

# Dev server tests  
zig run tests/unit/dev_server_tests.zig

# Debugger tests
zig run tests/unit/debugger_tests.zig

# Plugin registry tests
zig run tests/unit/plugin_registry_tests.zig
```

### Complete Test Suite

Run the comprehensive test suite:

```bash
# Run all tests with summary
zig run tests/unit/dev_tools_test_suite.zig

# Run with verbose output
zig run tests/unit/dev_tools_test_suite.zig -- --verbose

# Run with zig test framework
zig test tests/unit/dev_tools_test_suite.zig
```

### Build System Integration

Tests are integrated into the main build system:

```bash
# Run all unit tests
zig build test-unit

# Run specific dev tools tests
zig build test-dev-tools

# Run with verbose output
zig build test-dev-tools -- --verbose
```

## Test Configuration

The test suite supports configuration through `TestSuiteConfig`:

```zig
const config = TestSuiteConfig{
    .verbose = false,                    // Enable detailed output
    .run_performance_tests = true,       // Include performance benchmarks
    .run_integration_tests = true,       // Include cross-tool integration tests
    .run_error_handling_tests = true,    // Include error handling validation
    .max_test_duration_ms = 30_000,      // 30-second timeout per test
    .memory_limit_mb = 256,              // 256MB memory limit
};
```

## Test Features

### Mock Components

The tests include comprehensive mock implementations:

- **MockConnection** - Simulates HTTP connections for dev server testing
- **MockFile** - Simulates file operations for debugger testing  
- **MockPluginLoader** - Simulates plugin loading for registry testing

### Performance Testing

- **Error Reporting Performance** - Validates error reporting overhead (< 1ms per report)
- **File Operations Performance** - Validates file operation timing (< 10ms per operation)
- **Memory Usage Tracking** - Monitors memory consumption during tests

### Error Simulation

- **Network Errors** - Tests HTTP connection failures
- **File System Errors** - Tests file not found, permission denied, etc.
- **Plugin Errors** - Tests plugin loading and execution failures
- **Argument Parsing Errors** - Tests invalid command line arguments

## Test Metrics

The test suite provides detailed metrics:

- **Success Rate** - Percentage of tests passing
- **Performance Metrics** - Timing and memory usage statistics  
- **Coverage Statistics** - Test coverage across all tools
- **Error Handling Validation** - Consistency of error reporting

## Expected Output

### Successful Run

```
🔧 Zmin Dev Tools Unit Test Suite
==================================================
Configuration:
  Verbose Mode:        disabled
  Performance Tests:   enabled
  Integration Tests:   enabled
  Error Handling:      enabled
  Memory Limit:        256MB
  Timeout:             30000ms

🧪 Running Common Error Handling tests...
✅ Common Error Handling tests completed in 45.23ms

🧪 Running Dev Server tests...
✅ Dev Server tests completed in 78.91ms

🧪 Running Debugger tests...
✅ Debugger tests completed in 123.45ms

🧪 Running Plugin Registry tests...
✅ Plugin Registry tests completed in 67.89ms

🔗 Running integration tests...
✅ Integration tests completed

⚡ Running performance tests...
✅ Performance tests completed

📊 Test Suite Statistics
==================================================
Total Tests:     4
✅ Passed:       4
❌ Failed:       0
⏭️  Skipped:      0
🎯 Success Rate: 100.0%
⏱️  Duration:     345.67ms
💾 Peak Memory:  12.34MB

✅ All tests passed successfully!
```

## Contributing

When adding new dev tools functionality:

1. **Add unit tests** to the appropriate test module
2. **Update integration tests** if tools interact with each other
3. **Add performance tests** for critical functionality
4. **Update this README** with new test coverage

### Test Writing Guidelines

- Use descriptive test names that explain what is being tested
- Include both positive and negative test cases
- Test error conditions and edge cases
- Use mock components to isolate functionality being tested
- Validate both functionality and performance where applicable
- Follow the existing test patterns and structure

## Dependencies

The tests depend on:

- **Zig testing framework** - For assertions and test runner
- **Test framework** (`../test_framework.zig`) - For common testing utilities
- **Common errors** (`../../tools/common/errors.zig`) - For error handling infrastructure
- **Dev tools modules** - The actual tools being tested

## Troubleshooting

### Common Issues

1. **Tests timing out** - Increase `max_test_duration_ms` in config
2. **Memory limit exceeded** - Increase `memory_limit_mb` in config  
3. **File not found errors** - Ensure test fixtures exist in `../fixtures/`
4. **Build failures** - Ensure all dev tools compile successfully first

### Debug Mode

Run tests with verbose output to see detailed information:

```bash
zig run tests/unit/dev_tools_test_suite.zig -- --verbose
```

This will show:
- Individual test execution details
- Performance timing for each operation
- Error details when tests fail
- Memory usage statistics