// Unified interface for all minifier modes

const std = @import("std");
const modes = @import("modes");

const ProcessingMode = modes.ProcessingMode;
const ModeConfig = modes.ModeConfig;

/// Common interface for all minifier implementations
pub const MinifierInterface = struct {
    /// Minify JSON from reader to writer using specified mode
    pub fn minify(
        allocator: std.mem.Allocator,
        mode: ProcessingMode,
        reader: anytype,
        writer: anytype,
    ) !void {
        const config = ModeConfig.fromMode(mode);

        switch (mode) {
            .eco => {
                const EcoMinifier = @import("eco_minifier").EcoMinifier;
                var minifier = EcoMinifier.init(allocator);
                try minifier.minifyStreaming(reader, writer);
            },
            .sport => {
                const SportMinifier = @import("sport_minifier").SportMinifier;
                var minifier = SportMinifier.init(allocator);
                try minifier.minifyStreaming(reader, writer);
            },
            .turbo => {
                // Use the existing turbo module
                const turbo = @import("turbo_unified");
                var minifier = try turbo.TurboMinifier.init(allocator);

                // TURBO mode needs full file in memory
                const input = try reader.readAllAlloc(allocator, config.chunk_size);
                defer allocator.free(input);

                const output = try allocator.alloc(u8, input.len);
                defer allocator.free(output);

                const result = try minifier.minify(input, turbo.TurboConfig{});
                defer allocator.free(result.output);
                @memcpy(output[0..result.output.len], result.output);
                try writer.writeAll(output[0..result.output.len]);
            },
        }
    }

    /// Minify JSON string using specified mode
    pub fn minifyString(
        allocator: std.mem.Allocator,
        mode: ProcessingMode,
        input: []const u8,
    ) ![]u8 {
        var stream = std.io.fixedBufferStream(input);
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        try minify(allocator, mode, stream.reader(), output.writer());
        return output.toOwnedSlice();
    }

    /// Get memory requirements for a given file size and mode
    pub fn getMemoryRequirement(mode: ProcessingMode, file_size: usize) usize {
        return mode.getMemoryUsage(file_size);
    }

    /// Check if mode is supported on current platform
    pub fn isModeSupported(mode: ProcessingMode) bool {
        switch (mode) {
            .eco => return true, // Always supported
            .sport => return true, // Basic version always works
            .turbo => {
                // Check SIMD support
                const builtin = @import("builtin");
                return switch (builtin.cpu.arch) {
                    .x86_64 => std.Target.x86.featureSetHas(builtin.cpu.features, .sse2),
                    .aarch64 => true, // NEON is mandatory on AArch64
                    else => false,
                };
            },
        }
    }
};
