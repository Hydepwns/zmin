const std = @import("std");
const simd_utils = @import("simd_utils.zig");

/// Optimized buffer for high-performance I/O with SIMD alignment
pub const OptimizedBuffer = struct {
    data: []align(64) u8, // Cache-line aligned for optimal performance
    read_pos: usize,
    write_pos: usize,
    capacity: usize,
    allocator: std.mem.Allocator,

    const Self = @This();
    const CacheLineSize = 64;
    const DefaultSize = 256 * 1024; // 256KB default

    pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
        // Align size to cache line
        const aligned_size = (size + CacheLineSize - 1) & ~@as(usize, CacheLineSize - 1);

        return Self{
            .data = try allocator.alignedAlloc(u8, CacheLineSize, aligned_size),
            .read_pos = 0,
            .write_pos = 0,
            .capacity = aligned_size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
    }

    /// Get available space for writing
    pub fn availableWrite(self: *const Self) usize {
        return self.capacity - self.write_pos;
    }

    /// Get available data for reading
    pub fn availableRead(self: *const Self) usize {
        return self.write_pos - self.read_pos;
    }

    /// Write data to buffer
    pub fn write(self: *Self, data: []const u8) !usize {
        const available = self.availableWrite();
        const to_write = @min(data.len, available);

        if (to_write > 0) {
            @memcpy(self.data[self.write_pos..][0..to_write], data[0..to_write]);
            self.write_pos += to_write;
        }

        return to_write;
    }

    /// Read data from buffer
    pub fn read(self: *Self, output: []u8) usize {
        const available = self.availableRead();
        const to_read = @min(output.len, available);

        if (to_read > 0) {
            @memcpy(output[0..to_read], self.data[self.read_pos..][0..to_read]);
            self.read_pos += to_read;
        }

        return to_read;
    }

    /// Peek at data without consuming
    pub fn peek(self: *const Self) []const u8 {
        return self.data[self.read_pos..self.write_pos];
    }

    /// Consume data without copying
    pub fn consume(self: *Self, amount: usize) void {
        self.read_pos = @min(self.read_pos + amount, self.write_pos);
    }

    /// Compact buffer by moving unread data to beginning
    pub fn compact(self: *Self) void {
        const unread = self.availableRead();
        if (unread > 0 and self.read_pos > 0) {
            // Use memmove for overlapping regions
            std.mem.copyForwards(u8, self.data[0..unread], self.data[self.read_pos..self.write_pos]);
            self.read_pos = 0;
            self.write_pos = unread;
        } else if (unread == 0) {
            self.read_pos = 0;
            self.write_pos = 0;
        }
    }

    /// Reset buffer to empty state
    pub fn reset(self: *Self) void {
        self.read_pos = 0;
        self.write_pos = 0;
    }

    /// Get aligned slice for SIMD operations
    pub fn getAlignedSlice(self: *Self, alignment: usize) ?[]align(alignment) u8 {
        const available = self.availableRead();
        if (available < alignment) return null;

        // Find aligned position
        const addr = @intFromPtr(&self.data[self.read_pos]);
        const aligned_offset = (alignment - (addr % alignment)) % alignment;

        if (self.read_pos + aligned_offset + alignment <= self.write_pos) {
            const aligned_ptr = @as([*]align(alignment) u8, @ptrFromInt(addr + aligned_offset));
            const len = ((available - aligned_offset) / alignment) * alignment;
            return aligned_ptr[0..len];
        }

        return null;
    }
};

/// Ring buffer for continuous streaming with zero-copy
pub const RingBuffer = struct {
    data: []align(64) u8,
    mask: usize, // Size must be power of 2
    read_pos: std.atomic.Value(usize),
    write_pos: std.atomic.Value(usize),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, size_power: u8) !Self {
        const size = @as(usize, 1) << @intCast(size_power);

        return Self{
            .data = try allocator.alignedAlloc(u8, 64, size),
            .mask = size - 1,
            .read_pos = std.atomic.Value(usize).init(0),
            .write_pos = std.atomic.Value(usize).init(0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
    }

    /// Try to write data to ring buffer
    pub fn tryWrite(self: *Self, data: []const u8) ?usize {
        const write = self.write_pos.load(.acquire);
        const read = self.read_pos.load(.acquire);

        const available = if (write >= read)
            self.data.len - (write - read) - 1
        else
            read - write - 1;

        if (available < data.len) return null;

        // Write in up to two parts (wrap around)
        const part1_start = write & self.mask;
        const part1_len = @min(data.len, self.data.len - part1_start);
        @memcpy(self.data[part1_start..][0..part1_len], data[0..part1_len]);

        if (part1_len < data.len) {
            const part2_len = data.len - part1_len;
            @memcpy(self.data[0..part2_len], data[part1_len..]);
        }

        // Update write position
        _ = self.write_pos.fetchAdd(data.len, .release);

        return data.len;
    }

    /// Try to read data from ring buffer
    pub fn tryRead(self: *Self, output: []u8) ?usize {
        const read = self.read_pos.load(.acquire);
        const write = self.write_pos.load(.acquire);

        const available = if (write >= read)
            write - read
        else
            self.data.len - (read - write);

        if (available == 0) return null;

        const to_read = @min(output.len, available);

        // Read in up to two parts (wrap around)
        const part1_start = read & self.mask;
        const part1_len = @min(to_read, self.data.len - part1_start);
        @memcpy(output[0..part1_len], self.data[part1_start..][0..part1_len]);

        if (part1_len < to_read) {
            const part2_len = to_read - part1_len;
            @memcpy(output[part1_len..][0..part2_len], self.data[0..part2_len]);
        }

        // Update read position
        _ = self.read_pos.fetchAdd(to_read, .release);

        return to_read;
    }
};

/// Buffer pool for efficient allocation
pub const BufferPool = struct {
    buffers: std.ArrayList(OptimizedBuffer),
    available: std.ArrayList(usize),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    buffer_size: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, buffer_size: usize, pool_size: usize) !Self {
        var pool = Self{
            .buffers = std.ArrayList(OptimizedBuffer).init(allocator),
            .available = std.ArrayList(usize).init(allocator),
            .mutex = .{},
            .allocator = allocator,
            .buffer_size = buffer_size,
        };

        // Pre-allocate buffers
        try pool.buffers.ensureTotalCapacity(pool_size);
        try pool.available.ensureTotalCapacity(pool_size);

        for (0..pool_size) |i| {
            try pool.buffers.append(try OptimizedBuffer.init(allocator, buffer_size));
            try pool.available.append(i);
        }

        return pool;
    }

    pub fn deinit(self: *Self) void {
        for (self.buffers.items) |*buffer| {
            buffer.deinit();
        }
        self.buffers.deinit();
        self.available.deinit();
    }

    /// Acquire a buffer from the pool
    pub fn acquire(self: *Self) !*OptimizedBuffer {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.available.items.len > 0) {
            const index = self.available.pop();
            const buffer = &self.buffers.items[index];
            buffer.reset();
            return buffer;
        }

        // No available buffers, allocate new one
        try self.buffers.append(try OptimizedBuffer.init(self.allocator, self.buffer_size));
        return &self.buffers.items[self.buffers.items.len - 1];
    }

    /// Release a buffer back to the pool
    pub fn release(self: *Self, buffer: *OptimizedBuffer) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find buffer index
        for (self.buffers.items, 0..) |*b, i| {
            if (b == buffer) {
                self.available.append(i) catch {
                    // Pool is full, just reset the buffer
                    buffer.reset();
                };
                return;
            }
        }
    }
};
