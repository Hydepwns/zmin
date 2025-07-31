const std = @import("std");
const plugin_interface = @import("interface.zig");
const PluginInterface = plugin_interface.PluginInterface;
const PluginEntry = plugin_interface.PluginEntry;
const PluginError = plugin_interface.PluginError;
const PluginType = plugin_interface.PluginType;
const PluginInfo = plugin_interface.PluginInfo;

/// Plugin loader and manager
pub const PluginLoader = struct {
    allocator: std.mem.Allocator,
    plugins: std.ArrayList(PluginEntry),
    loaded_count: u32,
    plugin_paths: std.ArrayList([]const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .plugins = std.ArrayList(PluginEntry).init(allocator),
            .loaded_count = 0,
            .plugin_paths = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.plugins.items) |*plugin| {
            plugin.deinit();
        }
        self.plugins.deinit();

        for (self.plugin_paths.items) |path| {
            self.allocator.free(path);
        }
        self.plugin_paths.deinit();
    }

    /// Add a search path for plugins
    pub fn addPluginPath(self: *Self, path: []const u8) !void {
        const owned_path = try self.allocator.dupe(u8, path);
        try self.plugin_paths.append(owned_path);
    }

    /// Discover plugins in all registered paths
    pub fn discoverPlugins(self: *Self) !void {
        for (self.plugin_paths.items) |path| {
            try self.discoverPluginsInPath(path);
        }
    }

    /// Discover plugins in a specific path
    pub fn discoverPluginsInPath(self: *Self, path: []const u8) !void {
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.warn("Plugin directory not found: {s}", .{path});
                return;
            },
            else => return err,
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file) {
                // Look for shared libraries (.so, .dll, .dylib)
                if (std.mem.endsWith(u8, entry.name, ".so") or
                    std.mem.endsWith(u8, entry.name, ".dll") or
                    std.mem.endsWith(u8, entry.name, ".dylib"))
                {
                    const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, entry.name });
                    try self.registerPlugin(full_path);
                }
            }
        }
    }

    /// Register a plugin from a file path
    pub fn registerPlugin(self: *Self, path: []const u8) !void {
        const plugin_entry = PluginEntry.init(self.allocator, path);
        try self.plugins.append(plugin_entry);
        std.log.info("Registered plugin: {s}", .{path});
    }

    /// Load a specific plugin
    pub fn loadPlugin(self: *Self, index: usize) !void {
        if (index >= self.plugins.items.len) {
            return PluginError.PluginNotFound;
        }

        var plugin = &self.plugins.items[index];
        if (plugin.loaded) {
            return; // Already loaded
        }

        // In a real implementation, you would use dlopen/LoadLibrary here
        // For now, we'll simulate loading with a mock interface
        plugin.interface = try self.createMockInterface(plugin.path);

        // Initialize the plugin
        plugin.instance = plugin.interface.init(self.allocator) catch |err| {
            std.log.err("Failed to initialize plugin {s}: {any}", .{ plugin.path, err });
            return PluginError.PluginInitFailed;
        };

        plugin.loaded = true;
        self.loaded_count += 1;

        const info = plugin.interface.get_info();
        std.log.info("Loaded plugin: {s} v{s} ({s})", .{ info.name, info.version, @tagName(info.plugin_type) });
    }

    /// Load all registered plugins
    pub fn loadAllPlugins(self: *Self) !void {
        for (0..self.plugins.items.len) |i| {
            self.loadPlugin(i) catch |err| {
                std.log.warn("Failed to load plugin at index {d}: {any}", .{ i, err });
            };
        }
    }

    /// Unload a specific plugin
    pub fn unloadPlugin(self: *Self, index: usize) !void {
        if (index >= self.plugins.items.len) {
            return PluginError.PluginNotFound;
        }

        var plugin = &self.plugins.items[index];
        if (!plugin.loaded) {
            return;
        }

        if (plugin.instance) |instance| {
            plugin.interface.deinit(instance);
            plugin.instance = null;
        }

        plugin.loaded = false;
        self.loaded_count -= 1;

        std.log.info("Unloaded plugin: {s}", .{plugin.path});
    }

    /// Get plugins by type
    pub fn getPluginsByType(self: *Self, plugin_type: PluginType, allocator: std.mem.Allocator) ![]usize {
        var indices = std.ArrayList(usize).init(allocator);
        defer indices.deinit();

        for (self.plugins.items, 0..) |plugin, i| {
            if (plugin.loaded and plugin.interface.plugin_type == plugin_type) {
                try indices.append(i);
            }
        }

        return try indices.toOwnedSlice();
    }

    /// Process data with a specific plugin
    pub fn processWithPlugin(self: *Self, index: usize, input: []const u8) ![]u8 {
        if (index >= self.plugins.items.len) {
            return PluginError.PluginNotFound;
        }

        const plugin = &self.plugins.items[index];
        if (!plugin.loaded or plugin.instance == null) {
            return PluginError.PluginNotLoaded;
        }

        return plugin.interface.process(plugin.instance.?, input, self.allocator);
    }

    /// Get plugin information
    pub fn getPluginInfo(self: *Self, index: usize) !PluginInfo {
        if (index >= self.plugins.items.len) {
            return PluginError.PluginNotFound;
        }

        const plugin = &self.plugins.items[index];
        if (!plugin.loaded) {
            return PluginError.PluginNotLoaded;
        }

        return plugin.interface.get_info();
    }

    /// List all plugins
    pub fn listPlugins(self: *Self) void {
        std.log.info("=== Plugin Registry ===", .{});
        std.log.info("Total plugins: {d}", .{self.plugins.items.len});
        std.log.info("Loaded plugins: {d}", .{self.loaded_count});
        std.log.info("", .{});

        for (self.plugins.items, 0..) |plugin, i| {
            const status = if (plugin.loaded) "LOADED" else "REGISTERED";
            std.log.info("[{d}] {s} - {s}", .{ i, status, plugin.path });

            if (plugin.loaded) {
                const info = plugin.interface.get_info();
                std.log.info("    Name: {s} v{s}", .{ info.name, info.version });
                std.log.info("    Type: {s}", .{@tagName(info.plugin_type)});
                std.log.info("    Description: {s}", .{info.description});
            }
        }
    }

    /// Create a mock interface for testing/simulation
    fn createMockInterface(self: *Self, path: []const u8) !PluginInterface {
        _ = self;

        // Extract plugin name from path
        const basename = std.fs.path.basename(path);
        const plugin_type: PluginType = if (std.mem.indexOf(u8, basename, "minifier") != null)
            .minifier
        else if (std.mem.indexOf(u8, basename, "validator") != null)
            .validator
        else if (std.mem.indexOf(u8, basename, "optimizer") != null)
            .optimizer
        else
            .minifier;

        return PluginInterface{
            .name = basename,
            .version = "1.0.0",
            .plugin_type = plugin_type,
            .api_version = plugin_interface.PLUGIN_API_VERSION,
            .init = mockInit,
            .deinit = mockDeinit,
            .get_info = mockGetInfo,
            .process = mockProcess,
            .validate_config = mockValidateConfig,
        };
    }

    fn mockInit(allocator: std.mem.Allocator) anyerror!*anyopaque {
        _ = allocator;
        // Return a dummy pointer
        return @as(*anyopaque, @ptrFromInt(@as(usize, 0x12345678)));
    }

    fn mockDeinit(plugin: *anyopaque) void {
        _ = plugin;
        // Nothing to cleanup for mock
    }

    fn mockGetInfo() PluginInfo {
        return plugin_interface.PluginUtils.createDefaultInfo(
            "Mock Plugin",
            "1.0.0",
            "A simulated plugin for testing",
            .minifier,
        );
    }

    fn mockProcess(plugin: *anyopaque, input: []const u8, allocator: std.mem.Allocator) anyerror![]u8 {
        _ = plugin;
        // For mock plugins, just return a copy of the input
        return try allocator.dupe(u8, input);
    }

    fn mockValidateConfig(config: []const u8) bool {
        _ = config;
        return true;
    }
};

/// Plugin discovery utilities
pub const PluginDiscovery = struct {
    /// Standard plugin directories
    pub const STANDARD_PLUGIN_PATHS = [_][]const u8{
        "zig-out/plugins",
        "plugins",
        "/usr/local/lib/zmin/plugins",
        "/opt/zmin/plugins",
    };

    /// Auto-discover plugins in standard locations
    pub fn autoDiscover(loader: *PluginLoader) !void {
        for (STANDARD_PLUGIN_PATHS) |path| {
            loader.addPluginPath(path) catch |err| {
                std.log.debug("Could not add plugin path {s}: {any}", .{ path, err });
            };
        }

        try loader.discoverPlugins();
    }

    /// Validate plugin file
    pub fn validatePluginFile(path: []const u8) bool {
        // Check if file exists and is a valid shared library
        const file = std.fs.cwd().openFile(path, .{}) catch return false;
        defer file.close();

        // Basic validation - check file size and extension
        const stat = file.stat() catch return false;
        if (stat.size == 0) return false;

        return std.mem.endsWith(u8, path, ".so") or
            std.mem.endsWith(u8, path, ".dll") or
            std.mem.endsWith(u8, path, ".dylib");
    }
};
