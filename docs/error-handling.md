# Standardized Error Handling for Dev Tools

This document describes the standardized error handling approach implemented across all zmin dev tools.

## Overview

All dev tools now use a common error handling system defined in `tools/common/errors.zig`. This provides:

1. **Common Error Types** - A shared `DevToolError` enum with common error cases
2. **Error Context** - Structured error context with tool name, operation, and details
3. **Error Reporter** - Consistent error reporting with suggestions and verbose mode
4. **Helper Types** - File operations and process execution with built-in error handling

## Common Error Types

```zig
pub const DevToolError = error{
    // Configuration errors
    InvalidConfiguration,
    ConfigurationNotFound,
    ConfigurationParseError,
    InvalidConfigValue,
    
    // File system errors
    FileNotFound,
    DirectoryNotFound,
    PermissionDenied,
    FileReadError,
    FileWriteError,
    
    // Process errors
    ProcessSpawnFailed,
    ProcessExecutionFailed,
    ProcessTimeout,
    
    // Network errors (for dev server)
    BindFailed,
    ConnectionFailed,
    InvalidRequest,
    
    // Plugin errors
    PluginLoadFailed,
    PluginNotFound,
    PluginInitFailed,
    InvalidPlugin,
    
    // Argument errors
    InvalidArguments,
    MissingArgument,
    UnknownCommand,
    
    // Resource errors
    OutOfMemory,
    ResourceNotAvailable,
    
    // General errors
    NotImplemented,
    InternalError,
};
```

## Usage Pattern

### 1. Import the Error Module

```zig
const errors = @import("common/errors.zig");
const DevToolError = errors.DevToolError;
const ErrorReporter = errors.ErrorReporter;
```

### 2. Add Reporter to Your Tool Struct

```zig
const MyTool = struct {
    allocator: std.mem.Allocator,
    reporter: ErrorReporter,
    
    pub fn init(allocator: std.mem.Allocator) MyTool {
        return MyTool{
            .allocator = allocator,
            .reporter = ErrorReporter.init(allocator, "my-tool"),
        };
    }
};
```

### 3. Report Errors with Context

```zig
// Simple error reporting
self.reporter.report(DevToolError.FileNotFound, errors.context(
    "my-tool",
    "loading configuration"
));

// With details
self.reporter.report(DevToolError.InvalidArguments, errors.contextWithDetails(
    "my-tool",
    "parsing command line",
    "Unknown option: --foo"
));

// With file path
self.reporter.report(err, errors.contextWithFile(
    "my-tool",
    "reading input",
    "/path/to/file.json"
));
```

### 4. Use Helper Types

```zig
// File operations with automatic error reporting
const file_ops = errors.FileOps{ .reporter = &self.reporter };
const content = try file_ops.readFile(allocator, "config.json");

// Process execution with error handling
const process_ops = errors.ProcessOps{ .reporter = &self.reporter };
const result = try process_ops.exec(allocator, &[_][]const u8{"zig", "build"});
```

## Error Output Format

Errors are displayed in a consistent format:

```
❌ [tool-name] Error in operation (file: path/to/file.ext): details
   Error: ErrorType

💡 Suggestion: Helpful suggestion based on error type
```

With verbose mode enabled, stack traces are also displayed.

## Benefits

1. **Consistency** - All tools report errors in the same format
2. **Context** - Users get clear information about what went wrong
3. **Suggestions** - Helpful hints for common errors
4. **Debugging** - Verbose mode with stack traces for debugging
5. **Maintainability** - Centralized error types and handling logic

## Migration Guide

To migrate an existing tool to use standardized error handling:

1. Import the error module
2. Add `reporter: ErrorReporter` field to your main struct
3. Initialize the reporter in your init function
4. Replace `std.log.err` calls with `reporter.report`
5. Replace generic errors with specific `DevToolError` values
6. Use `FileOps` and `ProcessOps` for file/process operations
7. Add context to all error reports

## Example Implementation

See the updated implementations in:
- `tools/config_manager.zig` - Configuration management with file error handling
- `tools/hot_reloading.zig` - File watching with process execution errors
- `tools/profiler.zig` - Performance profiling with argument parsing errors