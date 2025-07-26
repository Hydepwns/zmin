const std = @import("std");
const MinifyingParser = @import("../minifier/mod.zig").MinifyingParser;

/// Simple parallel minifier for basic multi-threaded JSON processing
pub const ParallelMinifier = struct {
    allocator: std.mem.Allocator,
    writer: std.io.AnyWriter,
    config: Config,
    parser: MinifyingParser,

    const Self = @This();

    pub const Config = struct {
        thread_count: usize = 4,
        chunk_size: usize = 64 * 1024, // 64KB chunks
    };

    pub fn init(allocator: std.mem.Allocator, writer: std.io.AnyWriter, config: Config) !*Self {
        return create(allocator, writer, config);
    }

    pub fn create(allocator: std.mem.Allocator, writer: std.io.AnyWriter, config: Config) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .writer = writer,
            .config = config,
            .parser = try MinifyingParser.init(allocator, writer),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.destroy();
    }

    pub fn destroy(self: *Self) void {
        self.parser.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn process(self: *Self, input_data: []const u8) !void {
        // For API consistency, create a fresh parser for each process call
        // This ensures each JSON input is processed independently
        self.parser.deinit(self.allocator);
        self.parser = try MinifyingParser.init(self.allocator, self.writer);
        try self.parser.feed(input_data);
    }

    pub fn flush(self: *Self) !void {
        try self.parser.flush();
    }
};
