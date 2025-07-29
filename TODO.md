# zmin Development TODO List

## Current Status (2025-01-29)

**Build Status:**

- Main Project: ✅ 35/35 steps succeed (100%)
- Test Suite: 🔄 27/29 steps succeed (93.1%)
- Test Pass Rate: ✅ 104/105 tests passing (99%)

## High Priority Tasks

### 1. ~~Re-enable Concurrent Processing Test~~ ✅ COMPLETED

- ~~Currently commented out in `tests/integration/real_world_datasets.zig:334-339~~
- ~~Works fine in production but has issues with test allocator~~
- **Completed**: Created concurrent test using thread-safe GeneralPurposeAllocator instead of std.testing.allocator

### 2. ~~Fix Test Framework stderr Output Issue~~ ✅ COMPLETED

- ~~One test marked as failed due to stderr output from other tests~~
- **Completed**: Implemented conditional debug output system with debugPrint() function
- **Completed**: Suppressed all stderr output from tests to prevent false failures
- **Discovery**: Revealed actual regression test runtime failures that need investigation

### 3. ~~Investigate Regression Test Runtime Failures~~ ✅ COMPLETED

- ~~Actual test failures with InvalidObjectKey, NestingTooDeep, InvalidValue errors~~
- ~~Not cosmetic stderr issues - genuine runtime failures in regression tests~~
- **Root Cause Found**: Sport and Turbo modes only do whitespace removal without JSON validation
- **Discovery**: Eco mode correctly validates JSON and throws proper errors, but Sport/Turbo modes accept invalid JSON
- **New Critical Issue**: All modes need proper JSON validation while maintaining performance characteristics

### 4. ~~Fix JSON Validation in Sport and Turbo Modes~~ ✅ COMPLETED

- ✅ Create shared validation layer that all modes can use efficiently
- ✅ Update SportMinifier to use proper JSON validation while maintaining performance
- ✅ Update TurboMinifier strategies to use proper JSON validation
- ✅ Ensure all modes properly reject invalid JSON (trailing commas, deep nesting, etc.)
- ✅ Verify regression tests pass with consistent validation across all modes
- **Completed**: All modes now validate JSON syntax while maintaining their performance characteristics
- **Implementation**: Created `LightweightValidator` for consistent error detection across all modes
- **Result**: Sport and Turbo modes now properly reject invalid JSON with appropriate error messages

## Medium Priority Tasks

### 5. Complete Error Handling Integration

**dev_server.zig**

- [ ] Add `reporter: ErrorReporter` field to Server struct
- [ ] Update HTTP request handlers to use standardized error reporting
- [ ] Replace generic error returns with specific DevToolError types
- [ ] Use FileOps for file operations

**debugger.zig**

- [ ] Add `reporter: ErrorReporter` field to Debugger struct
- [ ] Update argument parsing with error reporting
- [ ] Replace file operations with FileOps wrapper
- [ ] Add ProcessOps for command execution

**plugin_registry.zig**

- [ ] Add `reporter: ErrorReporter` field to PluginRegistry struct
- [ ] Complete migration from std.log.err to reporter.report
- [ ] Add error context for plugin operations

### 6. Testing & Quality Assurance

- [ ] Create unit tests for dev tools:
  - config_manager, hot_reloading, dev_server
  - profiler, debugger, plugin_registry
- [ ] Add integration tests for tool interactions
- [ ] Test error handling edge cases

## Low Priority Tasks

### 7. CI/CD & Distribution

- [ ] Create GitHub Actions workflow
- [ ] Package dev tools for distribution
- [ ] Add installation instructions to README

### 8. Documentation Improvements

- [ ] Add usage examples for each dev tool
- [ ] Create troubleshooting section
- [ ] Add API documentation for plugin development

## Quick Reference

**Completed Recently:**

- ✅ Fixed test framework stderr output causing false failures
- ✅ Re-enabled concurrent processing test with thread-safe allocator
- ✅ Fixed unicode test allocation error
- ✅ Fixed regression test failures (performance thresholds)
- ✅ Fixed memory leak in turbo mode
- ✅ Resolved all compilation errors
- ✅ Fixed all module system circular dependencies
- ✅ **MAJOR**: Fixed JSON validation across all modes - Sport and Turbo now properly validate JSON
- ✅ Created LightweightValidator for consistent error handling across all modes
- ✅ Regression tests now pass with consistent behavior across eco/sport/turbo modes

**Known Issues:**

- ~~Regression tests have actual runtime failures (InvalidObjectKey, NestingTooDeep, InvalidValue)~~ ✅ RESOLVED
- ~~**NEW CRITICAL**: Sport and Turbo modes lack JSON validation - only do whitespace removal~~ ✅ RESOLVED

---
Last Updated: 2025-01-29
