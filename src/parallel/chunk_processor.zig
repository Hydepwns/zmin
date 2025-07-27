const std = @import("std");
const config = @import("config.zig");
const MinifyingParser = @import("../minifier/mod.zig").MinifyingParser;

pub const ChunkProcessor = struct {
    allocator: std.mem.Allocator,
    reusable_buffers: std.ArrayList(std.ArrayList(u8)),
    buffer_mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .reusable_buffers = std.ArrayList(std.ArrayList(u8)).init(allocator),
            .buffer_mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up reusable buffers
        for (self.reusable_buffers.items) |*buffer| {
            buffer.deinit();
        }
        self.reusable_buffers.deinit();
    }

    /// Get a reusable buffer, or create a new one if none available
    fn getBuffer(self: *Self) std.ArrayList(u8) {
        self.buffer_mutex.lock();
        defer self.buffer_mutex.unlock();

        if (self.reusable_buffers.items.len > 0) {
            const last_index = self.reusable_buffers.items.len - 1;
            const buffer = self.reusable_buffers.items[last_index];
            _ = self.reusable_buffers.orderedRemove(last_index);
            return buffer;
        }

        // No reusable buffer available, create new one
        return std.ArrayList(u8).init(self.allocator);
    }

    /// Return a buffer for reuse
    fn returnBuffer(self: *Self, mut_buffer: std.ArrayList(u8)) void {
        self.buffer_mutex.lock();
        defer self.buffer_mutex.unlock();

        var buffer = mut_buffer;
        // Clear the buffer but keep capacity for reuse
        buffer.items.len = 0;

        // Only keep a reasonable number of buffers to avoid excessive memory usage
        if (self.reusable_buffers.items.len < 8) {
            self.reusable_buffers.append(buffer) catch {
                // If we can't append, just deinit the buffer
                buffer.deinit();
            };
        } else {
            // Too many buffers already, just free this one
            buffer.deinit();
        }
    }

    pub fn processChunk(self: *Self, work_item: config.WorkItem) !config.ChunkResult {
        return self.processChunkWithAllocator(work_item, self.allocator);
    }

    pub fn processChunkWithAllocator(self: *Self, work_item: config.WorkItem, result_allocator: std.mem.Allocator) !config.ChunkResult {
        // Pre-allocate output buffer with estimated size to reduce reallocations
        const estimated_output_size = work_item.chunk.len; // Estimate output will be similar size to input
        var output = std.ArrayList(u8).init(self.allocator);
        defer output.deinit(); // Always clean up the output buffer
        try output.ensureTotalCapacity(estimated_output_size);

        // Create a thread-safe allocator for the parser with reasonable initial size
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var parser = try MinifyingParser.init(arena.allocator(), output.writer().any());
        defer parser.deinit(arena.allocator());

        // Process the chunk
        try parser.feed(work_item.chunk);
        try parser.flush();

        // Copy output to result using the provided allocator - avoid reallocation if possible
        const result_output = try result_allocator.alloc(u8, output.items.len);
        @memcpy(result_output, output.items);

        return config.ChunkResult.init(work_item.chunk_id, result_output);
    }

    pub fn processChunkWithWriter(self: *Self, work_item: config.WorkItem, writer: std.io.AnyWriter) !void {
        var parser = try MinifyingParser.init(self.allocator, writer);
        defer parser.deinit(self.allocator);

        try parser.feed(work_item.chunk);
        try parser.flush();
    }

    pub fn processChunkPretty(self: *Self, work_item: config.WorkItem, writer: std.io.AnyWriter, indent_size: u8) !void {
        var parser = try MinifyingParser.initPretty(self.allocator, writer, indent_size);
        defer parser.deinit(self.allocator);

        try parser.feed(work_item.chunk);
        try parser.flush();
    }

    pub fn validateChunk(self: *Self, chunk: []const u8) !void {
        // Basic validation - check if chunk contains valid JSON structure
        var parser = try MinifyingParser.init(self.allocator, std.io.null_writer.any());
        defer parser.deinit(self.allocator);

        try parser.feed(chunk);
        try parser.flush();
    }

    /// Find the next valid JSON boundary for chunking
    /// This ensures we don't split in the middle of strings, numbers, or other JSON tokens
    pub fn findNextBoundary(self: *Self, input: []const u8, start_pos: usize, max_chunk_size: usize) !usize {
        _ = self; // Suppress unused parameter warning

        if (start_pos >= input.len) {
            return input.len;
        }

        const end_pos = @min(start_pos + max_chunk_size, input.len);
        var pos = start_pos;
        var in_string = false;
        var escape_next = false;
        var brace_count: usize = 0;
        var bracket_count: usize = 0;

        while (pos < end_pos) : (pos += 1) {
            const byte = input[pos];

            if (escape_next) {
                escape_next = false;
                continue;
            }

            if (in_string) {
                if (byte == '\\') {
                    escape_next = true;
                } else if (byte == '"') {
                    in_string = false;
                }
                continue;
            }

            switch (byte) {
                '"' => {
                    in_string = true;
                },
                '{' => {
                    brace_count += 1;
                },
                '}' => {
                    if (brace_count > 0) {
                        brace_count -= 1;
                        // If we've closed all braces, this is a good boundary
                        if (brace_count == 0 and bracket_count == 0) {
                            return pos + 1;
                        }
                    }
                },
                '[' => {
                    bracket_count += 1;
                },
                ']' => {
                    if (bracket_count > 0) {
                        bracket_count -= 1;
                        // If we've closed all brackets, this is a good boundary
                        if (brace_count == 0 and bracket_count == 0) {
                            return pos + 1;
                        }
                    }
                },
                ',' => {
                    // Comma is a good boundary if we're at the top level
                    if (brace_count == 0 and bracket_count == 0) {
                        return pos + 1;
                    }
                },
                else => {},
            }
        }

        // If we can't find a good boundary, return the max size
        return end_pos;
    }

    pub fn estimateChunkSize(self: *Self, input: []const u8, target_chunk_size: usize) !usize {
        if (input.len <= target_chunk_size) {
            return input.len;
        }

        // Find the next valid boundary
        const boundary = try self.findNextBoundary(input, 0, target_chunk_size);
        return boundary;
    }

    pub fn splitIntoChunks(self: *Self, input: []const u8, chunk_size: usize) ![]config.WorkItem {
        var chunks = std.ArrayList(config.WorkItem).init(self.allocator);
        defer chunks.deinit();

        // Skip leading whitespace to find the start of JSON
        var start_pos: usize = 0;
        while (start_pos < input.len and std.ascii.isWhitespace(input[start_pos])) : (start_pos += 1) {}

        if (start_pos >= input.len) {
            return chunks.toOwnedSlice(); // Empty input
        }

        // Check if input is a JSON array - we can split array elements
        if (input[start_pos] == '[') {
            return try self.splitJsonArray(input[start_pos..], chunk_size);
        }

        // Check if input is a large object containing arrays that we can split
        if (input[start_pos] == '{' and input.len > chunk_size * 2) {
            return try self.splitLargeJsonObject(input[start_pos..], chunk_size);
        }

        // For single objects or other JSON types, use single chunk
        const chunk = input[start_pos..];
        try chunks.append(config.WorkItem.init(chunk, 0, true));

        return chunks.toOwnedSlice();
    }

    /// Free the allocated chunks from splitIntoChunks
    pub fn freeChunks(self: *Self, chunks: []config.WorkItem) void {
        for (chunks) |*chunk| {
            chunk.deinit(self.allocator);
        }
        self.allocator.free(chunks);
    }

    fn splitJsonArray(self: *Self, input: []const u8, target_chunk_size: usize) ![]config.WorkItem {
        var chunks = std.ArrayList(config.WorkItem).init(self.allocator);
        defer chunks.deinit();

        // For small arrays or when chunking would create overhead, use single chunk
        if (input.len < target_chunk_size) {
            try chunks.append(config.WorkItem.init(input, 0, true));
            return chunks.toOwnedSlice();
        }

        // Try to find array element boundaries and create chunks
        var current_batch = self.getBuffer();
        defer self.returnBuffer(current_batch);

        var pos: usize = 1; // Skip opening '['
        var chunk_id: usize = 0;
        var element_count: usize = 0;
        const max_elements_per_chunk = 200; // Balanced chunk size for performance

        try current_batch.append('['); // Start each chunk with '['

        while (pos < input.len) {
            // Skip whitespace
            while (pos < input.len and std.ascii.isWhitespace(input[pos])) : (pos += 1) {}

            if (pos >= input.len) break;

            // If we hit the closing ']', finish up
            if (input[pos] == ']') {
                // Close current batch and create final chunk
                if (element_count > 0) {
                    // Remove trailing comma if present
                    if (current_batch.items.len > 1 and current_batch.items[current_batch.items.len - 1] == ',') {
                        _ = current_batch.pop();
                    }
                }
                try current_batch.append(']');
                try chunks.append(config.WorkItem.initOwned(try self.allocator.dupe(u8, current_batch.items), chunk_id, true));
                break;
            }

            // Find the end of this array element
            const element_end = try self.findArrayElementEnd(input, pos);
            if (element_end > pos) {
                // Add this element to current batch
                try current_batch.appendSlice(input[pos..element_end]);
                element_count += 1;
                pos = element_end;

                // Skip comma and whitespace
                while (pos < input.len and (input[pos] == ',' or std.ascii.isWhitespace(input[pos]))) : (pos += 1) {}

                // Add comma for next element (if not at end)
                if (pos < input.len and input[pos] != ']') {
                    try current_batch.append(',');
                }

                // If batch is large enough, create a chunk
                if (element_count >= max_elements_per_chunk or current_batch.items.len >= target_chunk_size / 2) {
                    // Remove trailing comma if present
                    if (current_batch.items.len > 1 and current_batch.items[current_batch.items.len - 1] == ',') {
                        _ = current_batch.pop();
                    }
                    try current_batch.append(']');

                    const is_final = pos >= input.len - 1 or (pos < input.len and input[pos] == ']');
                    try chunks.append(config.WorkItem.initOwned(try self.allocator.dupe(u8, current_batch.items), chunk_id, is_final));

                    // Reset for next batch
                    chunk_id += 1;
                    element_count = 0;
                    current_batch.clearRetainingCapacity();
                    try current_batch.append('[');
                }
            } else {
                // Couldn't parse element, fall back to single chunk
                chunks.clearRetainingCapacity();
                try chunks.append(config.WorkItem.init(input, 0, true));
                return chunks.toOwnedSlice();
            }
        }

        // If we have no chunks (shouldn't happen), fall back to single chunk
        if (chunks.items.len == 0) {
            try chunks.append(config.WorkItem.init(input, 0, true));
        }

        return chunks.toOwnedSlice();
    }

    fn findArrayElementEnd(self: *Self, input: []const u8, start_pos: usize) !usize {
        _ = self;
        if (start_pos >= input.len) return start_pos;

        var pos = start_pos;
        var depth: i32 = 0;
        var in_string = false;
        var escape_next = false;

        while (pos < input.len) {
            const byte = input[pos];

            if (escape_next) {
                escape_next = false;
                pos += 1;
                continue;
            }

            if (in_string) {
                if (byte == '\\') {
                    escape_next = true;
                } else if (byte == '"') {
                    in_string = false;
                }
                pos += 1;
                continue;
            }

            switch (byte) {
                '"' => in_string = true,
                '{', '[' => depth += 1,
                '}', ']' => {
                    depth -= 1;
                    if (depth < 0) {
                        return pos; // Found end of current element
                    }
                },
                ',' => {
                    if (depth == 0) {
                        return pos; // Found end of current element
                    }
                },
                else => {},
            }
            pos += 1;
        }
        return pos;
    }

    fn splitLargeJsonObject(self: *Self, input: []const u8, target_chunk_size: usize) ![]config.WorkItem {
        var chunks = std.ArrayList(config.WorkItem).init(self.allocator);
        defer chunks.deinit();

        // For now, let's look for large arrays within the object and extract them
        // This is a simplified approach that looks for the pattern: "key": [...]
        var pos: usize = 1; // Skip opening '{'
        var found_large_array = false;

        while (pos < input.len - 1) {
            // Look for array start after a colon
            if (input[pos] == ':') {
                // Skip whitespace after colon
                pos += 1;
                while (pos < input.len and std.ascii.isWhitespace(input[pos])) : (pos += 1) {}

                if (pos < input.len and input[pos] == '[') {
                    // Found an array! Try to split it if it's large enough
                    const array_start = pos;
                    const array_end = try self.findMatchingBracket(input, array_start);

                    if (array_end > array_start and (array_end - array_start) > target_chunk_size) {
                        // Extract and split the large array
                        const array_content = input[array_start .. array_end + 1];
                        const array_chunks = try self.splitJsonArray(array_content, target_chunk_size);
                        defer self.allocator.free(array_chunks);

                        if (array_chunks.len > 1 and array_chunks.len <= 500) { // Limit chunks to prevent overwhelm
                            // Successfully split the array into multiple chunks
                            for (array_chunks, 0..) |chunk, i| {
                                try chunks.append(config.WorkItem.initOwned(chunk.chunk, i, i == array_chunks.len - 1));
                            }
                            found_large_array = true;
                            break;
                        }
                    }
                    pos = array_end + 1;
                } else {
                    pos += 1;
                }
            } else {
                pos += 1;
            }
        }

        // If we didn't find a large array to split, fall back to single chunk
        if (!found_large_array) {
            try chunks.append(config.WorkItem.init(input, 0, true));
        }

        return chunks.toOwnedSlice();
    }

    fn findMatchingBracket(self: *Self, input: []const u8, start_pos: usize) !usize {
        _ = self;
        if (start_pos >= input.len or input[start_pos] != '[') {
            return error.InvalidInput;
        }

        var pos = start_pos + 1;
        var depth: i32 = 1;
        var in_string = false;
        var escape_next = false;

        while (pos < input.len and depth > 0) {
            const byte = input[pos];

            if (escape_next) {
                escape_next = false;
                pos += 1;
                continue;
            }

            if (in_string) {
                if (byte == '\\') {
                    escape_next = true;
                } else if (byte == '"') {
                    in_string = false;
                }
                pos += 1;
                continue;
            }

            switch (byte) {
                '"' => in_string = true,
                '[' => depth += 1,
                ']' => {
                    depth -= 1;
                    if (depth == 0) {
                        return pos;
                    }
                },
                else => {},
            }
            pos += 1;
        }

        return error.UnmatchedBracket;
    }

    /// Check if a chunk is a complete JSON value
    pub fn isCompleteJsonValue(self: *Self, chunk: []const u8) bool {
        _ = self; // Suppress unused parameter warning

        if (chunk.len == 0) return false;

        // Skip leading whitespace
        var pos: usize = 0;
        while (pos < chunk.len and std.ascii.isSpace(chunk[pos])) : (pos += 1) {}
        if (pos >= chunk.len) return false;

        // Check for complete JSON values
        const first_char = chunk[pos];
        switch (first_char) {
            '{', '[' => {
                // For objects and arrays, we need to count braces/brackets
                var brace_count: usize = if (first_char == '{') 1 else 0;
                var bracket_count: usize = if (first_char == '[') 1 else 0;
                var in_string = false;
                var escape_next = false;

                pos += 1;
                while (pos < chunk.len) : (pos += 1) {
                    const byte = chunk[pos];

                    if (escape_next) {
                        escape_next = false;
                        continue;
                    }

                    if (in_string) {
                        if (byte == '\\') {
                            escape_next = true;
                        } else if (byte == '"') {
                            in_string = false;
                        }
                        continue;
                    }

                    switch (byte) {
                        '"' => in_string = true,
                        '{' => brace_count += 1,
                        '}' => brace_count -= 1,
                        '[' => bracket_count += 1,
                        ']' => bracket_count -= 1,
                        else => {},
                    }

                    // If we've closed all braces/brackets, we have a complete value
                    if (brace_count == 0 and bracket_count == 0) {
                        return true;
                    }
                }
                return false;
            },
            '"' => {
                // For strings, we need to find the closing quote
                var in_escape = false;
                pos += 1;
                while (pos < chunk.len) : (pos += 1) {
                    const byte = chunk[pos];
                    if (in_escape) {
                        in_escape = false;
                    } else if (byte == '\\') {
                        in_escape = true;
                    } else if (byte == '"') {
                        return true;
                    }
                }
                return false;
            },
            't', 'f', 'n' => {
                // For true, false, null - check if we have the complete token
                if (pos + 3 < chunk.len and std.mem.eql(u8, chunk[pos .. pos + 4], "true")) return true;
                if (pos + 4 < chunk.len and std.mem.eql(u8, chunk[pos .. pos + 5], "false")) return true;
                if (pos + 3 < chunk.len and std.mem.eql(u8, chunk[pos .. pos + 4], "null")) return true;
                return false;
            },
            '-', '0'...'9' => {
                // For numbers, we need to parse to the end
                // This is a simplified check - in practice you'd want more robust number parsing
                pos += 1;
                while (pos < chunk.len) : (pos += 1) {
                    const byte = chunk[pos];
                    if (!std.ascii.isDigit(byte) and byte != '.' and byte != 'e' and byte != 'E' and byte != '+' and byte != '-') {
                        break;
                    }
                }
                return true;
            },
            else => return false,
        }
    }
};
