//! Common Buffer and String Manipulation Utilities
//!
//! This module provides reusable buffer management and string manipulation
//! utilities to reduce duplication across the codebase.

const std = @import("std");
const constants = @import("constants.zig");
const simd_ops = @import("simd_buffer_ops.zig");

/// Dynamic buffer with automatic growth
pub const DynamicBuffer = struct {
    data: []u8,
    len: usize = 0,
    capacity: usize,
    allocator: std.mem.Allocator,
    growth_factor: f32 = 1.5,
    
    pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !DynamicBuffer {
        const data = try allocator.alloc(u8, initial_capacity);
        return DynamicBuffer{
            .data = data,
            .capacity = initial_capacity,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *DynamicBuffer) void {
        self.allocator.free(self.data);
    }
    
    /// Get current content as slice
    pub fn slice(self: *const DynamicBuffer) []const u8 {
        return self.data[0..self.len];
    }
    
    /// Get mutable slice
    pub fn sliceMut(self: *DynamicBuffer) []u8 {
        return self.data[0..self.len];
    }
    
    /// Ensure capacity for n more bytes
    pub fn ensureCapacity(self: *DynamicBuffer, additional: usize) !void {
        const needed = self.len + additional;
        if (needed > self.capacity) {
            const new_capacity = @max(needed, @as(usize, @intFromFloat(@as(f32, @floatFromInt(self.capacity)) * self.growth_factor)));
            const new_data = try self.allocator.realloc(self.data, new_capacity);
            self.data = new_data;
            self.capacity = new_capacity;
        }
    }
    
    /// Append bytes
    pub fn append(self: *DynamicBuffer, bytes: []const u8) !void {
        try self.ensureCapacity(bytes.len);
        @memcpy(self.data[self.len..self.len + bytes.len], bytes);
        self.len += bytes.len;
    }
    
    /// Append single byte
    pub fn appendByte(self: *DynamicBuffer, byte: u8) !void {
        try self.ensureCapacity(1);
        self.data[self.len] = byte;
        self.len += 1;
    }
    
    /// Clear buffer (keeps capacity)
    pub fn clear(self: *DynamicBuffer) void {
        self.len = 0;
    }
    
    /// Reset to specific size
    pub fn resize(self: *DynamicBuffer, new_len: usize) !void {
        if (new_len > self.capacity) {
            try self.ensureCapacity(new_len - self.len);
        }
        self.len = new_len;
    }
    
    /// Get writer interface
    pub fn writer(self: *DynamicBuffer) Writer {
        return .{ .context = self };
    }
    
    pub const Writer = std.io.Writer(*DynamicBuffer, error{OutOfMemory}, write);
    
    fn write(self: *DynamicBuffer, bytes: []const u8) error{OutOfMemory}!usize {
        try self.append(bytes);
        return bytes.len;
    }
};

/// Ring buffer for streaming operations
pub const RingBuffer = struct {
    data: []u8,
    read_pos: usize = 0,
    write_pos: usize = 0,
    capacity: usize,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !RingBuffer {
        const data = try allocator.alloc(u8, capacity);
        return RingBuffer{
            .data = data,
            .capacity = capacity,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *RingBuffer) void {
        self.allocator.free(self.data);
    }
    
    /// Get available space for writing
    pub fn availableWrite(self: *const RingBuffer) usize {
        if (self.write_pos >= self.read_pos) {
            return self.capacity - self.write_pos + self.read_pos - 1;
        } else {
            return self.read_pos - self.write_pos - 1;
        }
    }
    
    /// Get available data for reading
    pub fn availableRead(self: *const RingBuffer) usize {
        if (self.write_pos >= self.read_pos) {
            return self.write_pos - self.read_pos;
        } else {
            return self.capacity - self.read_pos + self.write_pos;
        }
    }
    
    /// Write data to buffer
    pub fn write(self: *RingBuffer, data: []const u8) usize {
        const available = self.availableWrite();
        const to_write = @min(data.len, available);
        
        var written: usize = 0;
        while (written < to_write) {
            const chunk_size = @min(to_write - written, self.capacity - self.write_pos);
            @memcpy(self.data[self.write_pos..self.write_pos + chunk_size], data[written..written + chunk_size]);
            self.write_pos = (self.write_pos + chunk_size) % self.capacity;
            written += chunk_size;
        }
        
        return written;
    }
    
    /// Read data from buffer
    pub fn read(self: *RingBuffer, buf: []u8) usize {
        const available = self.availableRead();
        const to_read = @min(buf.len, available);
        
        var bytes_read: usize = 0;
        while (bytes_read < to_read) {
            const chunk_size = @min(to_read - bytes_read, self.capacity - self.read_pos);
            @memcpy(buf[bytes_read..bytes_read + chunk_size], self.data[self.read_pos..self.read_pos + chunk_size]);
            self.read_pos = (self.read_pos + chunk_size) % self.capacity;
            bytes_read += chunk_size;
        }
        
        return bytes_read;
    }
    
    /// Peek at data without consuming
    pub fn peek(self: *const RingBuffer, buf: []u8) usize {
        const available = self.availableRead();
        const to_read = @min(buf.len, available);
        
        var read_pos = self.read_pos;
        var bytes_read: usize = 0;
        while (bytes_read < to_read) {
            const chunk_size = @min(to_read - bytes_read, self.capacity - read_pos);
            @memcpy(buf[bytes_read..bytes_read + chunk_size], self.data[read_pos..read_pos + chunk_size]);
            read_pos = (read_pos + chunk_size) % self.capacity;
            bytes_read += chunk_size;
        }
        
        return bytes_read;
    }
};

/// Stack-based buffer with fallback to heap
pub const StackBuffer = struct {
    stack_data: [constants.Buffer.STACK_LIMIT]u8 = undefined,
    heap_data: ?[]u8 = null,
    len: usize = 0,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) StackBuffer {
        return .{ .allocator = allocator };
    }
    
    pub fn deinit(self: *StackBuffer) void {
        if (self.heap_data) |data| {
            self.allocator.free(data);
        }
    }
    
    pub fn slice(self: *const StackBuffer) []const u8 {
        if (self.heap_data) |data| {
            return data[0..self.len];
        } else {
            return self.stack_data[0..self.len];
        }
    }
    
    pub fn ensureCapacity(self: *StackBuffer, capacity: usize) !void {
        if (capacity <= constants.Buffer.STACK_LIMIT) {
            // Fits in stack buffer
            return;
        }
        
        if (self.heap_data == null) {
            // Need to allocate heap buffer
            self.heap_data = try self.allocator.alloc(u8, capacity);
            // Copy existing data
            @memcpy(self.heap_data.?[0..self.len], self.stack_data[0..self.len]);
        } else if (capacity > self.heap_data.?.len) {
            // Need to grow heap buffer
            self.heap_data = try self.allocator.realloc(self.heap_data.?, capacity);
        }
    }
    
    pub fn append(self: *StackBuffer, data: []const u8) !void {
        const new_len = self.len + data.len;
        try self.ensureCapacity(new_len);
        
        if (self.heap_data) |heap| {
            @memcpy(heap[self.len..new_len], data);
        } else {
            @memcpy(self.stack_data[self.len..new_len], data);
        }
        
        self.len = new_len;
    }
};

/// String builder optimized for JSON construction
pub const JsonBuilder = struct {
    buffer: DynamicBuffer,
    depth: u32 = 0,
    first_in_container: std.ArrayList(bool),
    
    pub fn init(allocator: std.mem.Allocator) !JsonBuilder {
        return JsonBuilder{
            .buffer = try DynamicBuffer.init(allocator, constants.Buffer.MEDIUM),
            .first_in_container = std.ArrayList(bool).init(allocator),
        };
    }
    
    pub fn deinit(self: *JsonBuilder) void {
        self.buffer.deinit();
        self.first_in_container.deinit();
    }
    
    pub fn reset(self: *JsonBuilder) void {
        self.buffer.clear();
        self.depth = 0;
        self.first_in_container.clearRetainingCapacity();
    }
    
    pub fn slice(self: *const JsonBuilder) []const u8 {
        return self.buffer.slice();
    }
    
    pub fn startObject(self: *JsonBuilder) !void {
        try self.appendCommaIfNeeded();
        try self.buffer.appendByte('{');
        try self.first_in_container.append(true);
        self.depth += 1;
    }
    
    pub fn endObject(self: *JsonBuilder) !void {
        if (self.depth == 0) return error.UnbalancedContainers;
        try self.buffer.appendByte('}');
        _ = self.first_in_container.pop();
        self.depth -= 1;
    }
    
    pub fn startArray(self: *JsonBuilder) !void {
        try self.appendCommaIfNeeded();
        try self.buffer.appendByte('[');
        try self.first_in_container.append(true);
        self.depth += 1;
    }
    
    pub fn endArray(self: *JsonBuilder) !void {
        if (self.depth == 0) return error.UnbalancedContainers;
        try self.buffer.appendByte(']');
        _ = self.first_in_container.pop();
        self.depth -= 1;
    }
    
    pub fn addKey(self: *JsonBuilder, key: []const u8) !void {
        try self.appendCommaIfNeeded();
        try self.addString(key);
        try self.buffer.appendByte(':');
    }
    
    pub fn addString(self: *JsonBuilder, value: []const u8) !void {
        try self.appendCommaIfNeeded();
        try self.buffer.appendByte('"');
        
        for (value) |c| {
            switch (c) {
                '"' => try self.buffer.append("\\\""),
                '\\' => try self.buffer.append("\\\\"),
                '\n' => try self.buffer.append("\\n"),
                '\r' => try self.buffer.append("\\r"),
                '\t' => try self.buffer.append("\\t"),
                0x08 => try self.buffer.append("\\b"),
                0x0C => try self.buffer.append("\\f"),
                else => {
                    if (c < 0x20) {
                        var buf: [6]u8 = undefined;
                        const slice = try std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c});
                        try self.buffer.append(slice);
                    } else {
                        try self.buffer.appendByte(c);
                    }
                },
            }
        }
        
        try self.buffer.appendByte('"');
    }
    
    pub fn addNumber(self: *JsonBuilder, value: anytype) !void {
        try self.appendCommaIfNeeded();
        try std.fmt.format(self.buffer.writer(), "{}", .{value});
    }
    
    pub fn addBool(self: *JsonBuilder, value: bool) !void {
        try self.appendCommaIfNeeded();
        try self.buffer.append(if (value) "true" else "false");
    }
    
    pub fn addNull(self: *JsonBuilder) !void {
        try self.appendCommaIfNeeded();
        try self.buffer.append("null");
    }
    
    fn appendCommaIfNeeded(self: *JsonBuilder) !void {
        if (self.first_in_container.items.len > 0) {
            const index = self.first_in_container.items.len - 1;
            if (!self.first_in_container.items[index]) {
                try self.buffer.appendByte(',');
            } else {
                self.first_in_container.items[index] = false;
            }
        }
    }
};

/// Copy with alignment (SIMD-accelerated)
pub fn copyAligned(dest: []u8, src: []const u8, alignment: usize) void {
    _ = alignment;
    simd_ops.SimdOps.copyAligned(dest, src);
}

/// Fill buffer with pattern (SIMD-accelerated)
pub fn fillPattern(buffer: []u8, pattern: []const u8) void {
    simd_ops.SimdOps.fillPattern(buffer, pattern);
}

/// Find byte in buffer (SIMD-accelerated)
pub fn findByte(haystack: []const u8, needle: u8) ?usize {
    return simd_ops.SimdOps.findByte(haystack, needle);
}

/// Count occurrences of byte (SIMD-accelerated)
pub fn countByte(buffer: []const u8, byte: u8) usize {
    return simd_ops.SimdOps.countByte(buffer, byte);
}

/// Check if all bytes equal (SIMD-accelerated)
pub fn allBytesEqual(buffer: []const u8, value: u8) bool {
    return simd_ops.SimdOps.allBytesEqual(buffer, value);
}

// Tests
test "DynamicBuffer" {
    var buf = try DynamicBuffer.init(std.testing.allocator, 10);
    defer buf.deinit();
    
    try buf.append("hello");
    try buf.append(" world");
    try std.testing.expectEqualStrings("hello world", buf.slice());
    
    buf.clear();
    try std.testing.expectEqual(@as(usize, 0), buf.len);
}

test "RingBuffer" {
    var ring = try RingBuffer.init(std.testing.allocator, 10);
    defer ring.deinit();
    
    // Write and read
    const written = ring.write("hello");
    try std.testing.expectEqual(@as(usize, 5), written);
    
    var read_buf: [10]u8 = undefined;
    const read = ring.read(&read_buf);
    try std.testing.expectEqual(@as(usize, 5), read);
    try std.testing.expectEqualStrings("hello", read_buf[0..read]);
}

test "JsonBuilder" {
    var builder = try JsonBuilder.init(std.testing.allocator);
    defer builder.deinit();
    
    try builder.startObject();
    try builder.addKey("name");
    try builder.addString("John");
    try builder.addKey("age");
    try builder.addNumber(30);
    try builder.addKey("active");
    try builder.addBool(true);
    try builder.endObject();
    
    try std.testing.expectEqualStrings("{\"name\":\"John\",\"age\":30,\"active\":true}", builder.slice());
}