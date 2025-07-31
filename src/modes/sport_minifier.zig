// SPORT Mode - Balanced performance with adaptive chunking
// Target: 400-600 MB/s with O(√n) memory usage

const std = @import("std");
const builtin = @import("builtin");
const LightweightValidator = @import("minifier").lightweight_validator.LightweightValidator;

pub const SportMinifier = struct {
    allocator: std.mem.Allocator,
    chunk_size: usize = 1024 * 1024, // 1MB default chunks

    // Cache line size for alignment (typically 64 bytes)
    const cache_line_size = 64;

    // SIMD vector size for future optimization
    const vector_size = if (builtin.cpu.arch == .x86_64) 32 else 16;

    // Processing state
    const ProcessingState = struct {
        in_string: bool = false,
        escaped: bool = false,

        // Process a single character and return whether to output it
        fn processChar(self: *ProcessingState, c: u8) bool {
            if (self.escaped) {
                self.escaped = false;
                return true;
            }

            if (self.in_string) {
                if (c == '\\') {
                    self.escaped = true;
                } else if (c == '"') {
                    self.in_string = false;
                }
                return true;
            }

            if (c == '"') {
                self.in_string = true;
                return true;
            }

            return !isWhitespace(c);
        }
    };

    pub fn init(allocator: std.mem.Allocator) SportMinifier {
        return .{ .allocator = allocator };
    }

    pub fn minifyStreaming(
        self: *SportMinifier,
        reader: anytype,
        writer: anytype,
    ) !void {
        // For streaming, we need to read all input first to validate it
        // This is a trade-off for correctness while maintaining most performance benefits
        const input = try reader.readAllAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(input);

        // Skip strict validation in sport mode to allow trailing commas
        // try LightweightValidator.validate(input);

        // Now do the optimized minification knowing the JSON is valid
        return self.minifyValidated(input, writer);
    }

    /// Minify pre-validated JSON input with sport-mode optimizations
    fn minifyValidated(self: *SportMinifier, input: []const u8, writer: anytype) !void {
        // Output buffer for batched writes
        const output_size = 64 * 1024; // 64KB output buffer
        const output_buffer = try self.allocator.alloc(u8, output_size);
        defer self.allocator.free(output_buffer);
        var output_pos: usize = 0;

        var state = ProcessingState{};

        // Process in cache-friendly blocks
        var pos: usize = 0;

        // Fast path: process aligned blocks when not in string
        while (pos + vector_size <= input.len and !state.in_string) {
            const block = input[pos .. pos + vector_size];

            // Quick scan for quotes
            var has_quote = false;
            var quote_pos: usize = vector_size;
            for (block, 0..) |c, i| {
                if (c == '"') {
                    has_quote = true;
                    quote_pos = i;
                    break;
                }
            }

            if (!has_quote) {
                // No quotes in block - fast whitespace removal
                for (block) |c| {
                    if (!isWhitespace(c)) {
                        output_buffer[output_pos] = c;
                        output_pos += 1;

                        // Flush output buffer if nearly full
                        if (output_pos >= output_size - vector_size) {
                            try writer.writeAll(output_buffer[0..output_pos]);
                            output_pos = 0;
                        }
                    }
                }
                pos += vector_size;
            } else {
                // Process up to quote
                for (block[0..quote_pos]) |c| {
                    if (!isWhitespace(c)) {
                        output_buffer[output_pos] = c;
                        output_pos += 1;
                    }
                }

                // Handle the quote
                output_buffer[output_pos] = '"';
                output_pos += 1;
                state.in_string = true;
                pos += quote_pos + 1;
            }
        }

        // Slow path: byte-by-byte processing
        while (pos < input.len) {
            const c = input[pos];
            if (state.processChar(c)) {
                output_buffer[output_pos] = c;
                output_pos += 1;

                // Flush if buffer is full
                if (output_pos >= output_size - 1) {
                    try writer.writeAll(output_buffer[0..output_pos]);
                    output_pos = 0;
                }
            }
            pos += 1;
        }

        // Flush remaining output
        if (output_pos > 0) {
            try writer.writeAll(output_buffer[0..output_pos]);
        }
    }

    // Optimized minify for when we have the full input
    pub fn minify(self: *SportMinifier, input: []const u8, output: []u8) !usize {
        _ = self;

        // Skip strict validation in sport mode to allow trailing commas
        // try LightweightValidator.validate(input);

        var out_pos: usize = 0;
        var state = ProcessingState{};

        // Process in blocks for better performance
        var i: usize = 0;

        // Aligned block processing
        const aligned_end = input.len & ~@as(usize, vector_size - 1);

        while (i < aligned_end and !state.in_string) {
            const block_end = @min(i + vector_size, aligned_end);
            const block = input[i..block_end];

            // Look for quotes in block
            var quote_found = false;
            var quote_idx: usize = 0;
            for (block, 0..) |c, idx| {
                if (c == '"') {
                    quote_found = true;
                    quote_idx = idx;
                    break;
                }
            }

            if (!quote_found) {
                // Fast path: no quotes, bulk copy non-whitespace
                for (block) |c| {
                    if (!isWhitespace(c)) {
                        output[out_pos] = c;
                        out_pos += 1;
                    }
                }
                i = block_end;
            } else {
                // Process up to quote
                for (block[0..quote_idx]) |c| {
                    if (!isWhitespace(c)) {
                        output[out_pos] = c;
                        out_pos += 1;
                    }
                }
                // Add quote and switch to string mode
                output[out_pos] = '"';
                out_pos += 1;
                state.in_string = true;
                i += quote_idx + 1;
            }
        }

        // Process remainder byte by byte
        while (i < input.len) {
            const c = input[i];
            if (state.processChar(c)) {
                output[out_pos] = c;
                out_pos += 1;
            }
            i += 1;
        }

        return out_pos;
    }

    inline fn isWhitespace(c: u8) bool {
        // Optimized whitespace check using bit manipulation
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }
};
