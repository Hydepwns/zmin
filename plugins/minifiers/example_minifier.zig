const std = @import("std");
const plugin_interface = @import("plugin_interface");
const PluginInterface = plugin_interface.PluginInterface;
const PluginInfo = plugin_interface.PluginInfo;
const PluginType = plugin_interface.PluginType;

/// Example minifier plugin that removes extra whitespace
const ExampleMinifierPlugin = struct {
    allocator: std.mem.Allocator,
    config: Config,
    
    const Config = struct {
        remove_spaces: bool = true,
        remove_newlines: bool = true,
        preserve_strings: bool = true,
    };
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .config = Config{},
        };
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
    
    pub fn process(self: *Self, input: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();
        
        var in_string = false;
        var escape_next = false;
        var prev_char: u8 = 0;
        
        for (input) |char| {
            // Handle string detection
            if (self.config.preserve_strings) {
                if (!escape_next and char == '"') {
                    in_string = !in_string;
                }
                escape_next = (char == '\\' and !escape_next);
            }
            
            // Skip whitespace outside of strings
            if (!in_string) {
                if (self.config.remove_spaces and char == ' ') {
                    // Only keep space if it's significant
                    if (prev_char != ' ' and prev_char != '\t' and prev_char != '\n') {
                        // Check if space is needed between alphanumeric characters
                        if (std.ascii.isAlphanumeric(prev_char)) {
                            try result.append(' ');
                        }
                    }
                    prev_char = char;
                    continue;
                }
                
                if (self.config.remove_newlines and (char == '\n' or char == '\r')) {
                    prev_char = char;
                    continue;
                }
                
                if (char == '\t') {
                    prev_char = char;
                    continue;
                }
            }
            
            try result.append(char);
            prev_char = char;
        }
        
        return try result.toOwnedSlice();
    }
};

// Plugin interface implementation for internal use

// Zig plugin interface (for internal use)
pub fn getPluginInterface() PluginInterface {
    return PluginInterface{
        .name = "example_minifier",
        .version = "1.0.0",
        .plugin_type = .minifier,
        .api_version = plugin_interface.PLUGIN_API_VERSION,
        .init = zigInit,
        .deinit = zigDeinit,
        .get_info = zigGetInfo,
        .process = zigProcess,
        .validate_config = zigValidateConfig,
    };
}

fn zigInit(allocator: std.mem.Allocator) anyerror!*anyopaque {
    const plugin = try ExampleMinifierPlugin.init(allocator);
    return @as(*anyopaque, @ptrCast(plugin));
}

fn zigDeinit(instance: *anyopaque) void {
    const plugin = @as(*ExampleMinifierPlugin, @ptrCast(@alignCast(instance)));
    plugin.deinit();
}

fn zigGetInfo() PluginInfo {
    return PluginInfo{
        .name = "Example Minifier",
        .version = "1.0.0",
        .description = "A simple example minifier that removes whitespace",
        .author = "zmin Team",
        .license = "MIT",
        .plugin_type = .minifier,
        .api_version = plugin_interface.PLUGIN_API_VERSION,
        .capabilities = &[_][]const u8{ "whitespace_removal", "basic_minification" },
        .dependencies = &[_][]const u8{},
    };
}

fn zigProcess(instance: *anyopaque, input: []const u8, allocator: std.mem.Allocator) anyerror![]u8 {
    _ = allocator;
    const plugin = @as(*ExampleMinifierPlugin, @ptrCast(@alignCast(instance)));
    return plugin.process(input);
}

fn zigValidateConfig(config: []const u8) bool {
    _ = config;
    return true;
}