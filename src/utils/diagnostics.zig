//! Diagnostic and Debugging Utilities
//! 
//! Provides debugging and diagnostic tools for the production minifier

const std = @import("std");

/// Simple diagnostic utilities for debugging
pub fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (std.debug.runtime_safety) {
        std.debug.print(fmt, args);
    }
}

/// Performance timer for debugging
pub const Timer = struct {
    start_time: i128,
    
    pub fn start() Timer {
        return Timer{
            .start_time = std.time.nanoTimestamp(),
        };
    }
    
    pub fn elapsed(self: *Timer) u64 {
        const now = std.time.nanoTimestamp();
        return @as(u64, @intCast(now - self.start_time));
    }
    
    pub fn elapsedMs(self: *Timer) f64 {
        return @as(f64, @floatFromInt(self.elapsed())) / 1_000_000.0;
    }
};