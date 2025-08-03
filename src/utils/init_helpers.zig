//! Common Initialization Helpers
//!
//! This module provides reusable initialization patterns and helpers
//! to reduce boilerplate across the codebase.

const std = @import("std");

/// Common initialization pattern for allocator-based structs
pub fn InitWithAllocator(comptime T: type) type {
    return struct {
        /// Initialize with allocator and default values
        pub fn init(allocator: std.mem.Allocator) T {
            var instance: T = undefined;
            
            // Set allocator field if it exists
            if (@hasField(T, "allocator")) {
                instance.allocator = allocator;
            }
            
            // Initialize common fields with defaults
            inline for (std.meta.fields(T)) |field| {
                const field_name = field.name;
                
                // Skip allocator as we already set it
                if (std.mem.eql(u8, field_name, "allocator")) continue;
                
                // Initialize based on field type
                if (field.default_value) |default| {
                    @field(instance, field_name) = @as(field.type, default.*);
                } else {
                    @field(instance, field_name) = switch (@typeInfo(field.type)) {
                        .Bool => false,
                        .Int => 0,
                        .Float => 0.0,
                        .Optional => null,
                        .Pointer => if (field.type == []const u8) "" else undefined,
                        .Enum => @field(field.type, std.meta.fieldNames(field.type)[0]),
                        .Struct => if (@hasDecl(field.type, "init")) field.type.init(allocator) else undefined,
                        .Array => std.mem.zeroes(field.type),
                        else => undefined,
                    };
                }
            }
            
            return instance;
        }
        
        /// Initialize with allocator and config
        pub fn initWithConfig(allocator: std.mem.Allocator, config: anytype) T {
            var instance = init(allocator);
            
            // Apply config values
            inline for (std.meta.fields(@TypeOf(config))) |field| {
                if (@hasField(T, field.name)) {
                    @field(instance, field.name) = @field(config, field.name);
                }
            }
            
            return instance;
        }
    };
}

/// Helper to create a deinit function for types with allocator fields
pub fn createDeinit(comptime T: type) fn (*T) void {
    return struct {
        pub fn deinit(self: *T) void {
            // Look for fields that need cleanup
            inline for (std.meta.fields(T)) |field| {
                const field_type_info = @typeInfo(field.type);
                const field_ptr = &@field(self, field.name);
                
                switch (field_type_info) {
                    .Pointer => |ptr| {
                        // Handle slices that might need freeing
                        if (ptr.size == .Slice and ptr.is_const == false) {
                            if (@hasField(T, "allocator")) {
                                self.allocator.free(@field(self, field.name));
                            }
                        }
                    },
                    .Struct => {
                        // Call deinit on struct fields if they have it
                        if (@hasDecl(field.type, "deinit")) {
                            field_ptr.deinit();
                        }
                    },
                    else => {},
                }
            }
        }
    }.deinit;
}

/// Common configuration struct builder
pub fn Config(comptime fields: anytype) type {
    var struct_fields: [fields.len]std.builtin.Type.StructField = undefined;
    
    inline for (fields, 0..) |field_def, i| {
        struct_fields[i] = .{
            .name = field_def.name,
            .type = field_def.type,
            .default_value = if (@hasField(@TypeOf(field_def), "default")) 
                &field_def.default 
            else 
                null,
            .is_comptime = false,
            .alignment = @alignOf(field_def.type),
        };
    }
    
    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = &struct_fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

/// Memory statistics tracker mixin
pub fn WithMemoryStats(comptime T: type) type {
    return struct {
        pub const Self = @This();
        
        // Embed the original type
        base: T,
        
        // Memory statistics
        total_allocated: usize = 0,
        total_freed: usize = 0,
        peak_usage: usize = 0,
        allocation_count: usize = 0,
        current_usage: usize = 0,
        
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .base = if (@hasDecl(T, "init")) T.init(allocator) else T{},
            };
        }
        
        pub fn trackAllocation(self: *Self, size: usize) void {
            self.total_allocated += size;
            self.current_usage += size;
            self.allocation_count += 1;
            self.peak_usage = @max(self.peak_usage, self.current_usage);
        }
        
        pub fn trackDeallocation(self: *Self, size: usize) void {
            self.total_freed += size;
            self.current_usage -|= size;
        }
        
        pub fn getStats(self: *const Self) MemoryStats {
            return .{
                .total_allocated = self.total_allocated,
                .total_freed = self.total_freed,
                .peak_usage = self.peak_usage,
                .allocation_count = self.allocation_count,
                .current_usage = self.current_usage,
            };
        }
    };
}

/// Common memory statistics structure
pub const MemoryStats = struct {
    total_allocated: usize = 0,
    total_freed: usize = 0,
    peak_usage: usize = 0,
    allocation_count: usize = 0,
    current_usage: usize = 0,
    
    pub fn format(
        self: MemoryStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("Memory Stats: allocated={}, freed={}, peak={}, current={}, count={}", .{
            std.fmt.fmtIntSizeDec(self.total_allocated),
            std.fmt.fmtIntSizeDec(self.total_freed),
            std.fmt.fmtIntSizeDec(self.peak_usage),
            std.fmt.fmtIntSizeDec(self.current_usage),
            self.allocation_count,
        });
    }
};

/// Common thread pool configuration
pub const ThreadPoolConfig = struct {
    /// Number of threads (0 = auto-detect)
    thread_count: usize = 0,
    /// Stack size per thread
    stack_size: usize = 8 * 1024 * 1024,
    /// Thread name prefix
    name_prefix: []const u8 = "zmin-worker",
    /// CPU affinity settings
    pin_threads: bool = false,
};

/// Common chunk processing configuration
pub const ChunkConfig = struct {
    /// Size of each chunk
    chunk_size: usize = 64 * 1024,
    /// Minimum chunk size
    min_chunk_size: usize = 1024,
    /// Maximum chunk size  
    max_chunk_size: usize = 1024 * 1024,
    /// Overlap between chunks (for context)
    overlap_size: usize = 0,
};

/// Helper to create a standard init/deinit pattern
pub fn StandardLifecycle(comptime T: type) type {
    return struct {
        pub fn addTo(comptime Target: type) type {
            return struct {
                pub usingnamespace Target;
                pub usingnamespace InitWithAllocator(Target);
                
                pub const deinit = createDeinit(Target);
            };
        }
    };
}

// Tests
test "InitWithAllocator" {
    const TestStruct = struct {
        allocator: std.mem.Allocator,
        value: u32 = 42,
        optional: ?[]const u8 = null,
        flag: bool,
    };
    
    const Helper = InitWithAllocator(TestStruct);
    const instance = Helper.init(std.testing.allocator);
    
    try std.testing.expectEqual(std.testing.allocator, instance.allocator);
    try std.testing.expectEqual(@as(u32, 42), instance.value);
    try std.testing.expectEqual(@as(?[]const u8, null), instance.optional);
    try std.testing.expectEqual(false, instance.flag);
}

test "WithMemoryStats" {
    const TestType = struct {};
    const TrackedType = WithMemoryStats(TestType);
    
    var instance = TrackedType.init(std.testing.allocator);
    
    instance.trackAllocation(1024);
    instance.trackAllocation(2048);
    instance.trackDeallocation(1024);
    
    const stats = instance.getStats();
    try std.testing.expectEqual(@as(usize, 3072), stats.total_allocated);
    try std.testing.expectEqual(@as(usize, 1024), stats.total_freed);
    try std.testing.expectEqual(@as(usize, 3072), stats.peak_usage);
    try std.testing.expectEqual(@as(usize, 2048), stats.current_usage);
    try std.testing.expectEqual(@as(usize, 2), stats.allocation_count);
}