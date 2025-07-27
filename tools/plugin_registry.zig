const std = @import("std");
const plugin_loader = @import("plugin_loader");
const PluginLoader = plugin_loader.PluginLoader;
const PluginDiscovery = plugin_loader.PluginDiscovery;

/// Plugin registry management tool
const PluginRegistry = struct {
    allocator: std.mem.Allocator,
    loader: PluginLoader,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .loader = PluginLoader.init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.loader.deinit();
    }
    
    pub fn run(self: *Self, args: [][]const u8) !void {
        if (args.len == 0) {
            try self.showHelp();
            return;
        }
        
        const command = args[0];
        
        if (std.mem.eql(u8, command, "list")) {
            try self.listPlugins();
        } else if (std.mem.eql(u8, command, "discover")) {
            try self.discoverPlugins();
        } else if (std.mem.eql(u8, command, "load")) {
            try self.loadPlugins();
        } else if (std.mem.eql(u8, command, "test")) {
            try self.testPlugins();
        } else if (std.mem.eql(u8, command, "info")) {
            if (args.len < 2) {
                std.log.err("Usage: plugin-registry info <plugin_index>");
                return;
            }
            const index = std.fmt.parseInt(usize, args[1], 10) catch {
                std.log.err("Invalid plugin index: {s}", .{args[1]});
                return;
            };
            try self.showPluginInfo(index);
        } else if (std.mem.eql(u8, command, "benchmark")) {
            try self.benchmarkPlugins();
        } else {
            std.log.err("Unknown command: {s}", .{command});
            try self.showHelp();
        }
    }
    
    fn showHelp(self: *Self) !void {
        _ = self;
        
        std.log.info("Plugin Registry Management Tool");
        std.log.info("==============================");
        std.log.info("");
        std.log.info("Commands:");
        std.log.info("  list      - List all registered plugins");
        std.log.info("  discover  - Discover plugins in standard locations");
        std.log.info("  load      - Load all discovered plugins");
        std.log.info("  test      - Test all loaded plugins");
        std.log.info("  info <N>  - Show detailed info for plugin N");
        std.log.info("  benchmark - Benchmark plugin performance");
        std.log.info("");
        std.log.info("Examples:");
        std.log.info("  plugin-registry discover");
        std.log.info("  plugin-registry list");
        std.log.info("  plugin-registry load");
        std.log.info("  plugin-registry info 0");
        std.log.info("  plugin-registry test");
    }
    
    fn listPlugins(self: *Self) !void {
        try PluginDiscovery.autoDiscover(&self.loader);
        self.loader.listPlugins();
    }
    
    fn discoverPlugins(self: *Self) !void {
        std.log.info("🔍 Discovering plugins...");
        
        try PluginDiscovery.autoDiscover(&self.loader);
        
        std.log.info("✅ Plugin discovery completed");
        std.log.info("Found {} plugins", .{self.loader.plugins.items.len});
        
        if (self.loader.plugins.items.len > 0) {
            std.log.info("");
            self.loader.listPlugins();
        }
    }
    
    fn loadPlugins(self: *Self) !void {
        try PluginDiscovery.autoDiscover(&self.loader);
        
        std.log.info("🚀 Loading all plugins...");
        
        try self.loader.loadAllPlugins();
        
        std.log.info("✅ Plugin loading completed");
        std.log.info("Loaded {} out of {} plugins", .{ self.loader.loaded_count, self.loader.plugins.items.len });
        
        if (self.loader.loaded_count > 0) {
            std.log.info("");
            self.loader.listPlugins();
        }
    }
    
    fn testPlugins(self: *Self) !void {
        try PluginDiscovery.autoDiscover(&self.loader);
        try self.loader.loadAllPlugins();
        
        std.log.info("🧪 Testing all loaded plugins...");
        std.log.info("");
        
        const test_json = "{\"test\": \"data\", \"number\": 42, \"array\": [1, 2, 3]}";
        
        for (self.loader.plugins.items, 0..) |plugin, i| {
            if (!plugin.loaded) continue;
            
            const info = try self.loader.getPluginInfo(i);
            std.log.info("Testing plugin: {s}", .{info.name});
            
            const start_time = std.time.nanoTimestamp();
            const result = self.loader.processWithPlugin(i, test_json) catch |err| {
                std.log.err("  ❌ Test failed: {}", .{err});
                continue;
            };
            const end_time = std.time.nanoTimestamp();
            
            const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
            
            std.log.info("  ✅ Test passed in {d:.2}ms", .{duration_ms});
            std.log.info("  📄 Result length: {} bytes", .{result.len});
            
            // Show first 100 characters of result
            const preview_len = @min(result.len, 100);
            std.log.info("  📝 Preview: {s}{s}", .{ result[0..preview_len], if (result.len > 100) "..." else "" });
            std.log.info("");
            
            self.allocator.free(result);
        }
        
        std.log.info("✅ Plugin testing completed");
    }
    
    fn showPluginInfo(self: *Self, index: usize) !void {
        try PluginDiscovery.autoDiscover(&self.loader);
        try self.loader.loadAllPlugins();
        
        const info = self.loader.getPluginInfo(index) catch |err| {
            std.log.err("Failed to get plugin info: {}", .{err});
            return;
        };
        
        std.log.info("=== Plugin Information ===");
        std.log.info("Name: {s}", .{info.name});
        std.log.info("Version: {s}", .{info.version});
        std.log.info("Type: {s}", .{@tagName(info.plugin_type)});
        std.log.info("Description: {s}", .{info.description});
        std.log.info("Author: {s}", .{info.author});
        std.log.info("License: {s}", .{info.license});
        std.log.info("API Version: {s}", .{info.api_version});
        std.log.info("");
        std.log.info("Capabilities:");
        for (info.capabilities) |capability| {
            std.log.info("  - {s}", .{capability});
        }
        std.log.info("");
        std.log.info("Dependencies:");
        if (info.dependencies.len == 0) {
            std.log.info("  (none)");
        } else {
            for (info.dependencies) |dependency| {
                std.log.info("  - {s}", .{dependency});
            }
        }
    }
    
    fn benchmarkPlugins(self: *Self) !void {
        try PluginDiscovery.autoDiscover(&self.loader);
        try self.loader.loadAllPlugins();
        
        std.log.info("⚡ Benchmarking plugin performance...");
        std.log.info("");
        
        // Test with different JSON sizes
        const test_cases = [_]struct {
            name: []const u8,
            size: usize,
        }{
            .{ .name = "Small JSON", .size = 100 },
            .{ .name = "Medium JSON", .size = 1000 },
            .{ .name = "Large JSON", .size = 10000 },
        };
        
        for (test_cases) |test_case| {
            std.log.info("📊 {s} ({} bytes)", .{ test_case.name, test_case.size });
            
            // Generate test JSON
            var test_json = std.ArrayList(u8).init(self.allocator);
            defer test_json.deinit();
            
            try test_json.appendSlice("{\"data\": [");
            for (0..test_case.size / 20) |i| {
                if (i > 0) try test_json.appendSlice(", ");
                try test_json.writer().print("{{\"id\": {}, \"value\": \"item_{}\"}}", .{ i, i });
            }
            try test_json.appendSlice("]}");
            
            const json_str = try test_json.toOwnedSlice();
            defer self.allocator.free(json_str);
            
            // Benchmark each plugin
            for (self.loader.plugins.items, 0..) |plugin, i| {
                if (!plugin.loaded) continue;
                
                const info = try self.loader.getPluginInfo(i);
                
                // Run multiple iterations for better accuracy
                const iterations = 100;
                var total_time: i128 = 0;
                var successful_runs: u32 = 0;
                
                for (0..iterations) |_| {
                    const start_time = std.time.nanoTimestamp();
                    
                    if (self.loader.processWithPlugin(i, json_str)) |result| {
                        const end_time = std.time.nanoTimestamp();
                        total_time += end_time - start_time;
                        successful_runs += 1;
                        self.allocator.free(result);
                    } else |_| {
                        // Ignore errors for benchmarking
                    }
                }
                
                if (successful_runs > 0) {
                    const avg_time_ns = @divTrunc(total_time, successful_runs);
                    const avg_time_ms = @as(f64, @floatFromInt(avg_time_ns)) / 1_000_000.0;
                    
                    std.log.info("  {s}: {d:.3}ms avg ({} successful runs)", .{ info.name, avg_time_ms, successful_runs });
                } else {
                    std.log.info("  {s}: Failed all runs", .{info.name});
                }
            }
            
            std.log.info("");
        }
        
        std.log.info("✅ Benchmarking completed");
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    // Skip program name
    const command_args = if (args.len > 1) args[1..] else &[_][]const u8{};
    
    var registry = PluginRegistry.init(allocator);
    defer registry.deinit();
    
    try registry.run(command_args);
}