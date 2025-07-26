const std = @import("std");
const types = @import("types.zig");
const optimized_handlers = @import("optimized_handlers.zig");
const simd_utils = @import("simd_utils.zig");

/// Optimized parser that processes input in larger chunks using SIMD
pub const OptimizedMinifyingParser = struct {
    // Base parser for state management
    base: types.MinifyingParser,
    
    // Optimized buffer for batch processing
    input_buffer: AlignedBuffer,
    lookahead_buffer: AlignedBuffer,
    
    // Batch processing state
    batch_size: usize = 4096,
    pending_bytes: usize = 0,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter) !Self {
        return Self{
            .base = try types.MinifyingParser.init(allocator, writer),
            .input_buffer = try AlignedBuffer.init(allocator, 64 * 1024), // 64KB aligned buffer
            .lookahead_buffer = try AlignedBuffer.init(allocator, 4 * 1024), // 4KB lookahead
            .batch_size = 4096,
            .pending_bytes = 0,
        };
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.base.deinit(allocator);
        self.input_buffer.deinit(allocator);
        self.lookahead_buffer.deinit(allocator);
    }
    
    /// Feed data using optimized SIMD processing
    pub fn feedOptimized(self: *Self, input: []const u8) !void {
        // Copy to aligned buffer for SIMD processing
        if (self.pending_bytes > 0) {
            // Handle data that was pending from previous feed
            const total_size = self.pending_bytes + input.len;
            if (total_size <= self.input_buffer.capacity) {
                @memcpy(self.input_buffer.data[self.pending_bytes..][0..input.len], input);
                try self.processBatch(self.input_buffer.data[0..total_size]);
                self.pending_bytes = 0;
            } else {
                // Process what we have first
                try self.processBatch(self.input_buffer.data[0..self.pending_bytes]);
                self.pending_bytes = 0;
                try self.feedOptimized(input);
            }
        } else if (input.len >= self.batch_size) {
            // Process in aligned chunks
            var pos: usize = 0;
            while (pos + self.batch_size <= input.len) {
                @memcpy(self.input_buffer.data[0..self.batch_size], input[pos..][0..self.batch_size]);
                try self.processBatch(self.input_buffer.data[0..self.batch_size]);
                pos += self.batch_size;
            }
            
            // Save remaining bytes for next feed
            if (pos < input.len) {
                const remaining = input.len - pos;
                @memcpy(self.input_buffer.data[0..remaining], input[pos..]);
                self.pending_bytes = remaining;
            }
        } else {
            // Small input, save for batching
            @memcpy(self.input_buffer.data[self.pending_bytes..][0..input.len], input);
            self.pending_bytes += input.len;
            
            // Process if we have enough
            if (self.pending_bytes >= self.batch_size) {
                try self.processBatch(self.input_buffer.data[0..self.pending_bytes]);
                self.pending_bytes = 0;
            }
        }
    }
    
    /// Process a batch of data using SIMD optimizations
    fn processBatch(self: *Self, batch: []const u8) !void {
        var pos: usize = 0;
        
        while (pos < batch.len) {
            switch (self.base.state) {
                .TopLevel => {
                    try optimized_handlers.handleTopLevelOptimized(&self.base, batch, &pos);
                },
                .String, .ObjectKeyString => {
                    const bytes_processed = try optimized_handlers.handleStringOptimized(&self.base, batch, &pos);
                    if (bytes_processed == 0) break; // Need more data
                },
                .Number, .NumberDecimal, .NumberExponent => {
                    const bytes_processed = try optimized_handlers.handleNumberOptimized(&self.base, batch, &pos);
                    if (bytes_processed == 0) break; // Need more data
                },
                .ObjectValue => {
                    try optimized_handlers.handleObjectValueOptimized(&self.base, batch, &pos);
                },
                .ArrayValue => {
                    try optimized_handlers.handleArrayValueOptimized(&self.base, batch, &pos);
                },
                else => {
                    // Fall back to byte-by-byte processing for complex states
                    if (pos < batch.len) {
                        try self.base.feedByte(batch[pos]);
                        pos += 1;
                    }
                },
            }
            
            // Check if we need to flush output buffer
            if (self.base.output_pos > self.base.output_buffer.len - 1024) {
                try self.base.flush();
            }
        }
    }
    
    pub fn flush(self: *Self) !void {
        // Process any pending bytes
        if (self.pending_bytes > 0) {
            try self.processBatch(self.input_buffer.data[0..self.pending_bytes]);
            self.pending_bytes = 0;
        }
        
        // Flush base parser
        try self.base.flush();
    }
};

/// Aligned buffer for SIMD operations
pub const AlignedBuffer = struct {
    data: []align(32) u8,
    capacity: usize,
    
    pub fn init(allocator: std.mem.Allocator, size: usize) !AlignedBuffer {
        // Ensure size is multiple of vector size for SIMD
        const alignment = simd_utils.SimdUtils.vector_size;
        const aligned_size = (size + alignment - 1) & ~@as(usize, alignment - 1);
        
        return AlignedBuffer{
            .data = try allocator.alignedAlloc(u8, 32, aligned_size),
            .capacity = aligned_size,
        };
    }
    
    pub fn deinit(self: *AlignedBuffer, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Work item for parallel processing
pub const OptimizedWorkItem = struct {
    id: usize,
    input: []const u8,
    output: []u8,
    start_offset: usize,
    end_offset: usize,
    structural_boundary: ?usize,
    depth_at_start: i32,
    completed: std.atomic.Value(bool),
    error_flag: std.atomic.Value(bool),
    
    pub fn init(id: usize, input: []const u8, output: []u8) OptimizedWorkItem {
        return .{
            .id = id,
            .input = input,
            .output = output,
            .start_offset = 0,
            .end_offset = input.len,
            .structural_boundary = null,
            .depth_at_start = 0,
            .completed = std.atomic.Value(bool).init(false),
            .error_flag = std.atomic.Value(bool).init(false),
        };
    }
    
    /// Find optimal chunk boundaries for parallel processing
    pub fn findOptimalBoundaries(self: *OptimizedWorkItem) !void {
        // Use SIMD to find structural boundary
        self.structural_boundary = simd_utils.SimdUtils.findStructuralBoundarySimd(
            self.input,
            self.start_offset,
            self.depth_at_start
        );
    }
    
    /// Process this work item using SIMD optimizations
    pub fn processOptimized(self: *OptimizedWorkItem, allocator: std.mem.Allocator) !void {
        var output_stream = std.io.fixedBufferStream(self.output);
        var parser = try OptimizedMinifyingParser.init(allocator, output_stream.writer().any());
        defer parser.deinit(allocator);
        
        const end = self.structural_boundary orelse self.end_offset;
        const chunk = self.input[self.start_offset..end];
        
        parser.feedOptimized(chunk) catch |err| {
            self.error_flag.store(true, .monotonic);
            return err;
        };
        
        parser.flush() catch |err| {
            self.error_flag.store(true, .monotonic);
            return err;
        };
        
        self.completed.store(true, .release);
    }
};