//! Zero-Copy I/O Implementation using Memory Mapping
//!
//! Provides memory-mapped file I/O to eliminate intermediate buffer allocations
//! and achieve the 2x I/O performance improvement outlined in the TODO roadmap.

const std = @import("std");
const builtin = @import("builtin");

pub const ZeroCopyError = error{
    FileTooSmall,
    FileTooLarge,
    MemoryMapFailed,
    OutputWriteFailed,
    UnsupportedPlatform,
};

/// Zero-copy file processor for JSON minification
pub const ZeroCopyProcessor = struct {
    input_mmap: []align(4096) const u8,
    output_mmap: []align(4096) u8,
    input_fd: std.fs.File,
    output_fd: std.fs.File,
    input_size: usize,
    output_size: usize,

    const Self = @This();

    /// Initialize zero-copy processing for input and output files
    pub fn init(input_path: []const u8, output_path: []const u8) !Self {
        // Open input file
        const input_fd = std.fs.cwd().openFile(input_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.FileNotFound,
            else => return err,
        };
        errdefer input_fd.close();

        // Get input file size
        const input_stat = try input_fd.stat();
        const input_size = input_stat.size;

        // Validate input size (min 1KB, max 1GB for memory mapping)
        if (input_size < 1024) return ZeroCopyError.FileTooSmall;
        if (input_size > 1024 * 1024 * 1024) return ZeroCopyError.FileTooLarge;

        // Create/open output file
        const output_fd = std.fs.cwd().createFile(output_path, .{ .read = true }) catch |err| switch (err) {
            else => return err,
        };
        errdefer output_fd.close();

        // Pre-allocate output file (worst case: same size as input)
        try output_fd.setEndPos(input_size);

        // Memory map input file (read-only)
        const input_mmap = std.posix.mmap(
            null,
            input_size,
            std.posix.PROT.READ,
            .{ .TYPE = .PRIVATE },  // Copy-on-write, read-only
            input_fd.handle,
            0,
        ) catch return ZeroCopyError.MemoryMapFailed;
        errdefer std.posix.munmap(input_mmap);

        // Memory map output file (read-write)
        const output_mmap = std.posix.mmap(
            null,
            input_size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },  // Write changes to file
            output_fd.handle,
            0,
        ) catch {
            std.posix.munmap(input_mmap);
            return ZeroCopyError.MemoryMapFailed;
        };

        return Self{
            .input_mmap = @alignCast(input_mmap),
            .output_mmap = @alignCast(output_mmap),
            .input_fd = input_fd,
            .output_fd = output_fd,
            .input_size = input_size,
            .output_size = 0, // Will be set after processing
        };
    }

    /// Process JSON minification directly on memory-mapped regions
    pub fn processInPlace(self: *Self, minify_fn: *const fn([]const u8, []u8) usize) !usize {
        // Process directly on memory-mapped regions (zero-copy)
        const final_size = minify_fn(self.input_mmap, self.output_mmap);
        
        self.output_size = final_size;

        // Ensure data is written to disk
        // The minify function has already written to output_mmap, no need to copy

        // Sync changes to disk
        std.posix.msync(self.output_mmap, std.posix.MSF.SYNC) catch {};

        return final_size;
    }

    /// Get input data as slice (zero-copy read access)
    pub fn getInput(self: *const Self) []const u8 {
        return self.input_mmap;
    }

    /// Get output data as slice (zero-copy write access)
    pub fn getOutput(self: *Self) []u8 {
        return self.output_mmap[0..self.output_size];
    }

    /// Clean up resources and finalize output file
    pub fn deinit(self: *Self) void {
        // Unmap memory regions
        std.posix.munmap(self.input_mmap);
        std.posix.munmap(self.output_mmap);

        // Truncate output file to actual size
        self.output_fd.setEndPos(self.output_size) catch {};

        // Close file handles
        self.input_fd.close();
        self.output_fd.close();
    }

    /// Check if zero-copy I/O is supported on current platform
    pub fn isSupported() bool {
        return switch (builtin.os.tag) {
            .linux, .macos => true,
            .windows => false, // Windows has different mmap API
            else => false,
        };
    }
};

/// Zero-copy in-memory processor (for stdin/stdout)
pub const ZeroCopyMemory = struct {
    input: []const u8,
    output: []u8,
    output_size: usize,

    const Self = @This();

    pub fn init(input: []const u8, output_buffer: []u8) Self {
        return Self{
            .input = input,
            .output = output_buffer,
            .output_size = 0,
        };
    }

    pub fn processInPlace(self: *Self, minify_fn: *const fn([]const u8, []u8) usize) usize {
        const final_size = minify_fn(self.input, self.output);
        self.output_size = final_size;
        return final_size;
    }

    pub fn getOutput(self: *const Self) []const u8 {
        return self.output[0..self.output_size];
    }
};

/// Fallback to traditional I/O when zero-copy is not available
pub fn processFileTraditional(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: []const u8,
    minify_fn: *const fn(std.mem.Allocator, []const u8) anyerror![]u8,
) !void {
    // Read input file
    const input = try std.fs.cwd().readFileAlloc(allocator, input_path, 1024 * 1024 * 1024);
    defer allocator.free(input);

    // Minify
    const output = try minify_fn(allocator, input);
    defer allocator.free(output);

    // Write output file
    try std.fs.cwd().writeFile(.{ .sub_path = output_path, .data = output });
}