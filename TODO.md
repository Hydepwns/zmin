# zmin Development TODO List

## Overview

This document tracks remaining work items for the zmin JSON minifier project, including compilation fixes, error handling integration, testing, and future enhancements.

## High Priority Tasks

### 1. ~~Fix Remaining Dev Tool Compilation Errors~~ ✅ COMPLETED

All dev tool compilation errors have been successfully fixed:

- [x] `tools/profiler.zig` - Fixed undeclared identifier 'profiler' error and pointer type issues
- [x] `tools/debugger.zig` - Fixed variable type and argument count errors
- [x] `tools/plugin_registry.zig` - Fixed format string errors (missing {s} specifier)
- [x] `tools/config_manager.zig` - Fixed minor remaining issues
- [x] `src/plugins/loader.zig` - Fixed additional format string errors discovered during build

## Medium Priority Tasks

### 2. Complete Error Handling Integration

The following dev tools have error handling imports added but need full integration:

#### dev_server.zig

- [ ] Add `reporter: ErrorReporter` field to Server struct
- [ ] Update HTTP request handlers to use standardized error reporting
- [ ] Replace generic error returns with specific DevToolError types
- [ ] Use FileOps for file operations
- [ ] Add error context to all error reports

#### debugger.zig

- [ ] Add `reporter: ErrorReporter` field to Debugger struct
- [ ] Update argument parsing with error reporting
- [ ] Replace file operations with FileOps wrapper
- [ ] Add ProcessOps for command execution
- [ ] Implement proper error propagation with context

#### plugin_registry.zig

- [ ] Add `reporter: ErrorReporter` field to PluginRegistry struct
- [ ] Complete migration from std.log.err to reporter.report
- [ ] Add error context for plugin operations
- [ ] Handle plugin loading errors with proper context

### 3. Testing & Quality Assurance

- [ ] Create unit tests for all dev tools
  - [ ] config_manager tests
  - [ ] hot_reloading tests
  - [ ] dev_server tests
  - [ ] profiler tests
  - [ ] debugger tests
  - [ ] plugin_registry tests
- [ ] Add integration tests for tool interactions
- [ ] Test error handling edge cases
- [ ] Validate all tools work correctly with various inputs
- [ ] Create test fixtures for common scenarios

## Low Priority Tasks

### 4. CI/CD & Distribution

- [ ] Create GitHub Actions workflow
  - [ ] Build all dev tools on each commit
  - [ ] Run test suite
  - [ ] Generate code coverage reports
  - [ ] Create release artifacts
- [ ] Package dev tools for distribution
  - [ ] Create install script
  - [ ] Add to package managers (Homebrew, AUR, etc.)
- [ ] Add installation instructions to README
- [ ] Create release documentation

### 5. Documentation Improvements

- [ ] Add usage examples for each dev tool
- [ ] Create video tutorials/GIFs showing tool usage
- [ ] Document all configuration options
- [ ] Add troubleshooting section for common issues
- [ ] Create man pages for each tool
- [ ] Add API documentation for plugin development

## Future Enhancements

### 6. Feature Additions

- [ ] Add JSON output format to all tools for scripting
- [ ] Implement cross-platform compatibility
  - [ ] Windows support for all tools
  - [ ] macOS-specific optimizations
- [ ] Add plugin system for dev tools themselves
- [ ] Enhance dev-server web UI
  - [ ] Real-time performance graphs
  - [ ] WebSocket support for live updates
  - [ ] Plugin management interface
- [ ] Add telemetry/analytics (opt-in)
- [ ] Implement remote debugging capabilities

### 7. Code Quality Improvements

- [ ] Standardize CLI argument parsing
  - [ ] Create common argument parser module
  - [ ] Add consistent help formatting
- [ ] Add comprehensive logging with levels
  - [ ] Debug, Info, Warn, Error levels
  - [ ] Log rotation support
  - [ ] Structured logging (JSON format)
- [ ] Implement configuration file support
  - [ ] TOML configuration for all tools
  - [ ] Environment variable overrides
  - [ ] Configuration validation
- [ ] Add shell completion scripts
  - [ ] Bash completion
  - [ ] Zsh completion
  - [ ] Fish completion

## Completed Tasks ✅

### Compilation Fixes (2025-01-27) ✅ COMPLETED

#### Example Files

- [x] `examples/basic_usage.zig` - Fixed wrong number of arguments to minify function (now accepts allocator, input, mode)
- [x] `examples/mode_selection.zig` - Fixed type mismatch by casting microTimestamp to u64
- [x] `examples/streaming.zig` - Fixed missing StreamingMinifier by using MinifierInterface
- [x] `examples/parallel_batch.zig` - Fixed writeFile API changes and replaced atomic.Queue with mutex-based solution

#### Core Library Issues

- [x] `src/modes/turbo/strategies/streaming.zig` - Fixed `os.system` doesn't exist error by using hardcoded page size
- [x] `src/plugins/loader.zig` - Fixed unused variable warning by changing var to const

#### API Updates

- [x] Updated all `writeFile` calls to new API: `.{ .sub_path = path, .data = data }`
- [x] Changed `std.os.pipe()` to `std.posix.pipe()`
- [x] Changed `std.os.fd_t` to `std.posix.fd_t`
- [x] Updated `std.process.Child.exec` to `std.process.Child.run` with `RunResult` type
- [x] Updated deprecated `std.mem.split` to `std.mem.splitScalar`
- [x] Fixed `tools/common/errors.zig` - Changed ExecResult to RunResult

### Error Handling Standardization

- [x] Created common error types module (`tools/common/errors.zig`)
- [x] Implemented ErrorReporter with contextual error reporting
- [x] Added FileOps and ProcessOps helper types
- [x] Fully integrated error handling in config_manager.zig
- [x] Fully integrated error handling in hot_reloading.zig
- [x] Added basic error handling to profiler.zig
- [x] Created error handling documentation

### Documentation

- [x] Created comprehensive documentation suite
- [x] Fixed documentation inconsistencies
- [x] Created dev tools documentation
- [x] Added mode selection guide with interactive features

### Build System

- [x] Added all dev tools to build configuration
- [x] Fixed dev tools compilation errors
- [x] Integrated dev tools into main build process

## Quick Start for Contributors

To work on any of these items:

1. **For compilation fixes**: Start with the example files as they're simpler
2. **For error handling**: Use config_manager.zig as a reference implementation
3. **For testing**: Create a `tests/` directory with tool-specific test files
4. **For documentation**: Follow the existing style in `docs/`

## Priority Matrix

| Priority | Impact | Effort | Items |
|----------|--------|--------|-------|
| High     | High   | Low    | Compilation fixes |
| Medium   | Medium | Medium | Error handling, Testing |
| Low      | Low    | High   | CI/CD, Documentation |
| Future   | Variable | Variable | Feature enhancements |

## Build Status

As of 2025-01-27, the build succeeds for all 35 out of 35 steps: ✅

- All example files compile successfully ✅
- Core library compiles successfully ✅
- All dev tools compile successfully ✅
- All compilation errors have been resolved ✅

## Notes

- ✅ All compilation errors have been fixed - ready for release
- Error handling integration improves user experience significantly
- Testing ensures reliability and prevents regressions
- CI/CD automates quality checks and releases
- Documentation reduces support burden

---
Last Updated: 2025-01-27
