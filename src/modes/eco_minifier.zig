// ECO Mode - Memory-efficient streaming JSON minifier
// This is the refactored version of the original minifier

const std = @import("std");
const MinifyingParser = @import("../minifier/mod.zig").MinifyingParser;

pub const EcoMinifier = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) EcoMinifier {
        return .{ .allocator = allocator };
    }
    
    pub fn minifyStreaming(
        self: *EcoMinifier,
        reader: anytype, 
        writer: anytype,
    ) !void {
        // Use the existing MinifyingParser in streaming mode
        var parser = try MinifyingParser.init(self.allocator, writer.any());
        defer parser.deinit(self.allocator);
        
        // 64KB buffer for true O(1) memory usage
        var buffer: [64 * 1024]u8 = undefined;
        
        while (true) {
            const bytes_read = try reader.read(&buffer);
            if (bytes_read == 0) break;
            
            try parser.feed(buffer[0..bytes_read]);
        }
        
        try parser.flush();
    }
    
    /// Direct minification for small inputs
    pub fn minifyDirect(
        self: *EcoMinifier,
        input: []const u8,
        output: []u8,
    ) !usize {
        var stream = std.io.fixedBufferStream(output);
        var parser = try MinifyingParser.init(self.allocator, stream.writer().any());
        defer parser.deinit(self.allocator);
        
        try parser.feed(input);
        try parser.flush();
        
        return stream.pos;
    }
};