const std = @import("std");
const Allocator = std.mem.Allocator;
const MinifyingParser = @import("../minifier/mod.zig").MinifyingParser;

pub const SimpleParallelMinifier = struct {
    // Configuration
    thread_count: usize,
    chunk_size: usize,

    // Output management
    output_buffer: std.ArrayList(u8),
    allocator: Allocator,

    // Input buffering
    input_buffer: std.ArrayList(u8),

    // State tracking
    error_state: ?anyerror,

    const Self = @This();

    // Configuration options
    pub const Config = struct {
        thread_count: usize = 1,
        chunk_size: usize = 64 * 1024, // 64KB default
    };

    pub fn init(allocator: Allocator, _: std.io.AnyWriter, config: Config) !Self {
        // Validate and adjust configuration
        const actual_thread_count = if (config.thread_count == 0) 1 else config.thread_count;
        const max_threads = std.Thread.getCpuCount() catch 4;
        const final_thread_count = @min(actual_thread_count, max_threads);

        return Self{
            .thread_count = final_thread_count,
            .chunk_size = config.chunk_size,
            .output_buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
            .input_buffer = std.ArrayList(u8).init(allocator),
            .error_state = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.output_buffer.deinit();
        self.input_buffer.deinit();
    }

    pub fn process(self: *Self, input: []const u8) !void {
        if (self.error_state) |err| return err;

        // Add input to buffer
        try self.input_buffer.appendSlice(input);

        // Process the input immediately
        try self.processSingleThreaded(input);

        // Clear the input buffer since we've processed it
        self.input_buffer.clearRetainingCapacity();
    }

    pub fn flush(self: *Self) !void {
        if (self.error_state) |err| return err;

        // No need to process anything in flush since we process immediately in process()
        // This method is kept for API compatibility
    }

    fn processSingleThreaded(self: *Self, input: []const u8) !void {
        // Create a temporary parser to process this input
        var parser = try MinifyingParser.init(self.allocator, self.output_buffer.writer().any());
        defer parser.deinit(self.allocator);

        try parser.feed(input);
        try parser.flush();
    }

    pub fn getOutput(self: *Self) []const u8 {
        return self.output_buffer.items;
    }

    pub fn clearOutput(self: *Self) void {
        self.output_buffer.clearRetainingCapacity();
    }

    pub fn copyOutputTo(self: *Self, target: *std.ArrayList(u8)) !void {
        try target.appendSlice(self.output_buffer.items);
    }
};
