//! Simple Public API for zmin JSON Minifier
//! 
//! This module provides a clean, intuitive interface for common JSON minification tasks.
//! Designed for ease of use - 90% of users should only need these functions.
//!
//! Performance: Automatically optimized for 5+ GB/s throughput
//! Compatibility: Cross-platform (Linux, macOS, Windows)
//! Safety: Memory-safe with robust error handling

const std = @import("std");
const core = @import("../core/minifier.zig");

/// Simple JSON minification - allocates output buffer
/// 
/// This is the most straightforward way to minify JSON.
/// The function automatically detects the optimal processing strategy
/// and returns a minified JSON string.
///
/// Example:
/// ```zig
/// const input = "{ \"name\" : \"John\" , \"age\" : 30 }";
/// const minified = try zmin.minify(allocator, input);
/// defer allocator.free(minified);
/// // Result: `{"name":"John","age":30}`
/// ```
///
/// Args:
///   - allocator: Memory allocator for output buffer
///   - input: JSON string to minify
///
/// Returns:
///   - Minified JSON string (caller owns memory)
///
/// Errors:
///   - OutOfMemory: Insufficient memory for output buffer
///   - InvalidJson: Input is not valid JSON
///   - ProcessingError: Internal processing error
pub fn minify(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    // Validate input is not empty
    if (input.len == 0) {
        return allocator.dupe(u8, "");
    }
    
    // Use core minifier with automatic optimization
    return core.MinifierEngine.minify(allocator, input, .{
        .optimization_level = .automatic,
        .validate_input = true,
        .preserve_precision = true,
    });
}

/// Minify JSON to a writer interface
///
/// This function streams the minified output directly to a writer,
/// avoiding the need to allocate a large output buffer. Ideal for
/// processing large JSON files or streaming applications.
///
/// Example:
/// ```zig
/// const input = "{ \"large\" : \"json\" }";
/// var output_buffer = std.ArrayList(u8).init(allocator);
/// defer output_buffer.deinit();
/// 
/// try zmin.minifyToWriter(input, output_buffer.writer());
/// const minified = output_buffer.items;
/// ```
///
/// Args:
///   - input: JSON string to minify
///   - writer: Any writer interface (File, ArrayList, etc.)
///
/// Errors:
///   - InvalidJson: Input is not valid JSON
///   - WriteError: Writer failed to accept output
///   - ProcessingError: Internal processing error
pub fn minifyToWriter(input: []const u8, writer: anytype) !void {
    // Validate input
    if (input.len == 0) return;
    
    // Use core minifier with streaming output
    var minifier = try core.MinifierEngine.initStreaming(writer, .{
        .optimization_level = .automatic,
        .validate_input = true,
        .buffer_size = 64 * 1024, // 64KB buffer
    });
    defer minifier.deinit();
    
    try minifier.process(input);
    try minifier.flush();
}

/// Minify JSON with pre-allocated output buffer
///
/// For performance-critical applications where you want to control
/// memory allocation. The output buffer must be large enough to
/// hold the minified result (input.len is always sufficient).
///
/// Example:
/// ```zig
/// const input = "{ \"name\" : \"value\" }";
/// var output_buffer: [1024]u8 = undefined;
/// 
/// const minified_len = try zmin.minifyToBuffer(input, &output_buffer);
/// const minified = output_buffer[0..minified_len];
/// ```
///
/// Args:
///   - input: JSON string to minify
///   - output_buffer: Pre-allocated buffer for minified output
///
/// Returns:
///   - Length of minified data written to buffer
///
/// Errors:
///   - InvalidJson: Input is not valid JSON
///   - BufferTooSmall: Output buffer insufficient for minified result
///   - ProcessingError: Internal processing error
pub fn minifyToBuffer(input: []const u8, output_buffer: []u8) !usize {
    // Validate input and buffer
    if (input.len == 0) return 0;
    if (output_buffer.len < input.len) {
        return error.BufferTooSmall;
    }
    
    // Use core minifier with fixed buffer
    return core.MinifierEngine.minifyToBuffer(input, output_buffer, .{
        .optimization_level = .automatic,
        .validate_input = true,
    });
}

/// Validate JSON without minification
///
/// Quickly check if a JSON string is valid without performing
/// the full minification process. Uses the same high-performance
/// parser as the minifier.
///
/// Example:
/// ```zig
/// const valid_json = "{ \"valid\": true }";
/// const invalid_json = "{ invalid json }";
/// 
/// try zmin.validate(valid_json);   // Returns successfully
/// zmin.validate(invalid_json) catch |err| {
///     // Handle validation error
/// };
/// ```
///
/// Args:
///   - input: JSON string to validate
///
/// Errors:
///   - InvalidJson: Input is not valid JSON
///   - ProcessingError: Internal processing error
pub fn validate(input: []const u8) !void {
    if (input.len == 0) return;
    
    // Use core validator (fast path without output generation)
    try core.MinifierEngine.validateOnly(input);
}

/// Get performance statistics for the last minification operation
///
/// Returns detailed performance metrics including throughput,
/// optimization strategy used, and hardware utilization.
/// Useful for performance analysis and optimization.
///
/// Example:
/// ```zig
/// const input = "{ \"data\": [1, 2, 3] }";
/// _ = try zmin.minify(allocator, input);
/// 
/// const stats = zmin.getLastStats();
/// std.debug.print("Throughput: {d:.2} GB/s\n", .{stats.throughput_gbps});
/// ```
///
/// Returns:
///   - Performance statistics structure
pub fn getLastStats() core.PerformanceStats {
    return core.MinifierEngine.getLastStats();
}

/// Performance statistics structure
pub const PerformanceStats = core.PerformanceStats;

/// Error types that can be returned by the simple API
pub const Error = error{
    OutOfMemory,
    InvalidJson,
    BufferTooSmall,
    WriteError,
    ProcessingError,
};

// Re-export common types for convenience
pub const JsonError = core.JsonError;
pub const ValidationResult = core.ValidationResult;

//
// Convenience functions for common patterns
//

/// Minify JSON from file to file
///
/// Read JSON from input file, minify it, and write to output file.
/// Handles large files efficiently with streaming processing.
///
/// Example:
/// ```zig
/// try zmin.minifyFile(allocator, "input.json", "output.json");
/// ```
pub fn minifyFile(allocator: std.mem.Allocator, input_path: []const u8, output_path: []const u8) !void {
    const input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();
    
    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();
    
    // For large files, use streaming processing
    const file_size = try input_file.getEndPos();
    if (file_size > 1024 * 1024) { // > 1MB
        try minifyStream(input_file.reader().any(), output_file.writer().any());
    } else {
        // For small files, read everything into memory
        const content = try input_file.readToEndAlloc(allocator, file_size);
        defer allocator.free(content);
        
        const minified = try minify(allocator, content);
        defer allocator.free(minified);
        
        try output_file.writeAll(minified);
    }
}

/// Minify JSON with streaming processing
///
/// Process JSON data from any reader to any writer with
/// streaming to handle arbitrarily large inputs efficiently.
///
/// Example:
/// ```zig
/// const stdin = std.io.getStdIn().reader();
/// const stdout = std.io.getStdOut().writer();
/// try zmin.minifyStream(stdin.any(), stdout.any());
/// ```
pub fn minifyStream(reader: std.io.AnyReader, writer: std.io.AnyWriter) !void {
    var minifier = try core.MinifierEngine.initStreaming(writer, .{
        .optimization_level = .automatic,
        .validate_input = true,
        .chunk_size = 64 * 1024, // 64KB chunks
    });
    defer minifier.deinit();
    
    try minifier.processStream(reader);
    try minifier.flush();
}

/// Estimate minified size without actually minifying
///
/// Quickly estimate how much the JSON will compress.
/// Useful for memory allocation planning.
///
/// Example:
/// ```zig
/// const input = "{ \"name\" : \"John\" }";
/// const estimated_size = zmin.estimateMinifiedSize(input);
/// const buffer = try allocator.alloc(u8, estimated_size);
/// ```
pub fn estimateMinifiedSize(input: []const u8) usize {
    return core.MinifierEngine.estimateOutputSize(input);
}

/// Check if the library supports hardware acceleration
///
/// Returns information about available hardware optimizations
/// like SIMD instructions, multi-core processing, etc.
///
/// Example:
/// ```zig
/// const caps = zmin.getCapabilities();
/// if (caps.has_avx512) {
///     std.debug.print("AVX-512 acceleration available\n");
/// }
/// ```
pub fn getCapabilities() core.HardwareCapabilities {
    return core.MinifierEngine.getHardwareCapabilities();
}

//
// Test helpers for development and validation
//

/// Compare two JSON strings for semantic equality
///
/// Useful for testing - compares the actual JSON content
/// rather than string equality, ignoring whitespace differences.
pub fn jsonEquals(a: []const u8, b: []const u8) bool {
    return core.MinifierEngine.semanticEquals(a, b);
}

/// Generate test JSON data of specified size
/// 
/// Creates realistic JSON data for benchmarking and testing.
/// Only available in debug builds.
pub fn generateTestData(allocator: std.mem.Allocator, size: usize) ![]u8 {
    if (std.debug.runtime_safety) {
        return core.TestUtils.generateRealisticJson(allocator, size);
    } else {
        @compileError("generateTestData only available in debug builds");
    }
}