const std = @import("std");

/// Plugin API version for compatibility checking
pub const PLUGIN_API_VERSION = "1.0.0";

/// Plugin types supported by zmin
pub const PluginType = enum {
    minifier,
    validator,
    optimizer,
    formatter,
    analyzer,
};

/// Plugin interface for all zmin plugins
pub const PluginInterface = struct {
    name: []const u8,
    version: []const u8,
    plugin_type: PluginType,
    api_version: []const u8,

    /// Initialize the plugin
    init: *const fn (allocator: std.mem.Allocator) anyerror!*anyopaque,

    /// Cleanup plugin resources
    deinit: *const fn (plugin: *anyopaque) void,

    /// Get plugin information
    get_info: *const fn () PluginInfo,

    /// Process data according to plugin type
    process: *const fn (plugin: *anyopaque, input: []const u8, allocator: std.mem.Allocator) anyerror![]u8,

    /// Validate plugin configuration
    validate_config: *const fn (config: []const u8) bool,
};

/// Plugin information structure
pub const PluginInfo = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8,
    license: []const u8,
    plugin_type: PluginType,
    api_version: []const u8,
    capabilities: []const []const u8,
    dependencies: []const []const u8,
};

/// Plugin configuration structure
pub const PluginConfig = struct {
    enabled: bool = true,
    priority: u32 = 100,
    options: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) PluginConfig {
        return PluginConfig{
            .options = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *PluginConfig) void {
        self.options.deinit();
    }

    pub fn setOption(self: *PluginConfig, key: []const u8, value: []const u8) !void {
        try self.options.put(key, value);
    }

    pub fn getOption(self: *PluginConfig, key: []const u8) ?[]const u8 {
        return self.options.get(key);
    }
};

/// Plugin registry entry
pub const PluginEntry = struct {
    interface: PluginInterface,
    config: PluginConfig,
    handle: ?*anyopaque = null,
    instance: ?*anyopaque = null,
    loaded: bool = false,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) PluginEntry {
        return PluginEntry{
            .interface = undefined,
            .config = PluginConfig.init(allocator),
            .path = path,
        };
    }

    pub fn deinit(self: *PluginEntry) void {
        if (self.instance) |instance| {
            self.interface.deinit(instance);
        }
        self.config.deinit();
    }
};

/// Plugin manager errors
pub const PluginError = error{
    PluginNotFound,
    InvalidPluginFormat,
    IncompatibleApiVersion,
    PluginLoadFailed,
    PluginInitFailed,
    PluginNotLoaded,
    InvalidConfiguration,
};

/// Utility functions for plugin development
pub const PluginUtils = struct {
    /// Validate API version compatibility
    pub fn isApiVersionCompatible(plugin_version: []const u8, required_version: []const u8) bool {
        // Simple version comparison - in practice, you'd want semantic versioning
        return std.mem.eql(u8, plugin_version, required_version);
    }

    /// Create default plugin info
    pub fn createDefaultInfo(
        name: []const u8,
        version: []const u8,
        description: []const u8,
        plugin_type: PluginType,
    ) PluginInfo {
        return PluginInfo{
            .name = name,
            .version = version,
            .description = description,
            .author = "Unknown",
            .license = "MIT",
            .plugin_type = plugin_type,
            .api_version = PLUGIN_API_VERSION,
            .capabilities = &[_][]const u8{},
            .dependencies = &[_][]const u8{},
        };
    }

    /// Validate plugin interface
    pub fn validateInterface(interface: *const PluginInterface) bool {
        if (interface.name.len == 0) return false;
        if (interface.version.len == 0) return false;
        if (!isApiVersionCompatible(interface.api_version, PLUGIN_API_VERSION)) return false;
        return true;
    }
};

/// Test utilities for plugin development
pub const PluginTest = struct {
    /// Create a mock plugin for testing
    pub fn createMockPlugin(allocator: std.mem.Allocator, name: []const u8, plugin_type: PluginType) !PluginInterface {
        _ = allocator;

        return PluginInterface{
            .name = name,
            .version = "1.0.0",
            .plugin_type = plugin_type,
            .api_version = PLUGIN_API_VERSION,
            .init = mockInit,
            .deinit = mockDeinit,
            .get_info = mockGetInfo,
            .process = mockProcess,
            .validate_config = mockValidateConfig,
        };
    }

    fn mockInit(allocator: std.mem.Allocator) anyerror!*anyopaque {
        _ = allocator;
        return @as(*anyopaque, @ptrFromInt(@as(usize, 0x1234)));
    }

    fn mockDeinit(plugin: *anyopaque) void {
        _ = plugin;
    }

    fn mockGetInfo() PluginInfo {
        return PluginUtils.createDefaultInfo("MockPlugin", "1.0.0", "Test plugin", .minifier);
    }

    fn mockProcess(plugin: *anyopaque, input: []const u8, allocator: std.mem.Allocator) anyerror![]u8 {
        _ = plugin;
        return try allocator.dupe(u8, input);
    }

    fn mockValidateConfig(config: []const u8) bool {
        _ = config;
        return true;
    }
};
