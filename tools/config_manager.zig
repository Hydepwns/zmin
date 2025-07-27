const std = @import("std");

/// Configuration manager for zmin build system
const ConfigManager = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }
    
    pub fn run(self: *Self, args: [][]const u8) !void {
        if (args.len == 0) {
            try self.showHelp();
            return;
        }
        
        const command = args[0];
        
        if (std.mem.eql(u8, command, "show")) {
            try self.showConfig();
        } else if (std.mem.eql(u8, command, "reset")) {
            try self.resetConfig();
        } else if (std.mem.eql(u8, command, "validate")) {
            try self.validateConfig();
        } else if (std.mem.eql(u8, command, "profile")) {
            if (args.len < 2) {
                try self.showProfileHelp();
                return;
            }
            
            const profile_command = args[1];
            if (std.mem.eql(u8, profile_command, "list")) {
                try self.listProfiles();
            } else if (std.mem.eql(u8, profile_command, "apply")) {
                if (args.len < 3) {
                    std.log.err("Usage: config-manager profile apply <profile_name>");
                    return;
                }
                try self.applyProfile(args[2]);
            } else {
                std.log.err("Unknown profile command: {s}", .{profile_command});
                try self.showProfileHelp();
            }
        } else if (std.mem.eql(u8, command, "set")) {
            if (args.len < 3) {
                std.log.err("Usage: config-manager set <key> <value>");
                return;
            }
            try self.setConfigValue(args[1], args[2]);
        } else if (std.mem.eql(u8, command, "get")) {
            if (args.len < 2) {
                std.log.err("Usage: config-manager get <key>");
                return;
            }
            try self.getConfigValue(args[1]);
        } else {
            std.log.err("Unknown command: {s}", .{command});
            try self.showHelp();
        }
    }
    
    fn showHelp(self: *Self) !void {
        _ = self;
        
        std.log.info("Configuration Manager");
        std.log.info("====================");
        std.log.info("");
        std.log.info("Commands:");
        std.log.info("  show           - Show current configuration");
        std.log.info("  reset          - Reset to default configuration");
        std.log.info("  validate       - Validate configuration files");
        std.log.info("  set <key> <val>- Set configuration value");
        std.log.info("  get <key>      - Get configuration value");
        std.log.info("  profile list   - List available profiles");
        std.log.info("  profile apply  - Apply a configuration profile");
        std.log.info("");
        std.log.info("Examples:");
        std.log.info("  config-manager show");
        std.log.info("  config-manager set build.optimize ReleaseFast");
        std.log.info("  config-manager profile apply performance");
        std.log.info("  config-manager validate");
    }
    
    fn showProfileHelp(self: *Self) !void {
        _ = self;
        
        std.log.info("Profile Management:");
        std.log.info("  list   - List available profiles");
        std.log.info("  apply  - Apply a profile");
        std.log.info("");
        std.log.info("Usage:");
        std.log.info("  config-manager profile list");
        std.log.info("  config-manager profile apply <profile_name>");
    }
    
    fn showConfig(self: *Self) !void {
        std.log.info("📋 Current Configuration");
        std.log.info("========================");
        
        // Try to read the main config file
        const config_content = std.fs.cwd().readFileAlloc(self.allocator, "config/zmin.toml", 10000) catch |err| {
            if (err == error.FileNotFound) {
                std.log.info("No configuration file found. Using defaults.");
                try self.showDefaultConfig();
                return;
            }
            std.log.err("Failed to read config file: {}", .{err});
            return;
        };
        defer self.allocator.free(config_content);
        
        std.log.info("Configuration file: config/zmin.toml");
        std.log.info("");
        std.log.info("{s}", .{config_content});
        
        // Show active profile if any
        try self.showActiveProfile();
    }
    
    fn showDefaultConfig(self: *Self) !void {
        _ = self;
        
        std.log.info("Default Configuration:");
        std.log.info("");
        std.log.info("[build]");
        std.log.info("optimize = \"ReleaseFast\"");
        std.log.info("target = \"native\"");
        std.log.info("enable_simd = true");
        std.log.info("enable_parallel = true");
        std.log.info("max_threads = 0  # 0 = auto-detect");
        std.log.info("");
        std.log.info("[features]");
        std.log.info("json_validation = true");
        std.log.info("schema_validation = true");
        std.log.info("memory_profiling = false");
        std.log.info("debug_mode = false");
        std.log.info("");
        std.log.info("[minifier]");
        std.log.info("default_mode = \"sport\"");
        std.log.info("preserve_formatting = false");
        std.log.info("remove_whitespace = true");
        std.log.info("compress_keys = true");
        std.log.info("");
        std.log.info("[plugins]");
        std.log.info("enabled = true");
        std.log.info("load_path = \"zig-out/plugins\"");
        std.log.info("auto_discover = true");
    }
    
    fn showActiveProfile(self: *Self) !void {
        const profile_content = std.fs.cwd().readFileAlloc(self.allocator, "config/.active_profile", 100) catch |err| {
            if (err == error.FileNotFound) {
                std.log.info("📝 No active profile");
                return;
            }
            std.log.err("Failed to read active profile: {}", .{err});
            return;
        };
        defer self.allocator.free(profile_content);
        
        const trimmed = std.mem.trim(u8, profile_content, " \t\n\r");
        std.log.info("📝 Active profile: {s}", .{trimmed});
    }
    
    fn resetConfig(self: *Self) !void {
        _ = self;
        std.log.info("🔄 Resetting configuration to defaults...");
        
        // Remove current config file
        std.fs.cwd().deleteFile("config/zmin.toml") catch |err| {
            if (err != error.FileNotFound) {
                std.log.warn("Could not delete existing config: {}", .{err});
            }
        };
        
        // Remove active profile
        std.fs.cwd().deleteFile("config/.active_profile") catch |err| {
            if (err != error.FileNotFound) {
                std.log.warn("Could not delete active profile: {}", .{err});
            }
        };
        
        std.log.info("✅ Configuration reset completed");
        std.log.info("Run 'zig build config' to regenerate default configuration");
    }
    
    fn validateConfig(self: *Self) !void {
        std.log.info("🔍 Validating configuration...");
        
        var errors: u32 = 0;
        
        // Check main config file
        const config_content = std.fs.cwd().readFileAlloc(self.allocator, "config/zmin.toml", 10000) catch |err| {
            if (err == error.FileNotFound) {
                std.log.warn("❌ Main config file not found: config/zmin.toml");
                errors += 1;
            } else {
                std.log.err("❌ Failed to read config file: {}", .{err});
                errors += 1;
            }
            return;
        };
        defer self.allocator.free(config_content);
        
        // Basic TOML validation (simplified)
        if (try self.validateTomlSyntax(config_content)) {
            std.log.info("✅ Main config file syntax is valid");
        } else {
            std.log.err("❌ Main config file has syntax errors");
            errors += 1;
        }
        
        // Check for required sections
        const required_sections = [_][]const u8{ "[build]", "[features]", "[minifier]" };
        for (required_sections) |section| {
            if (std.mem.indexOf(u8, config_content, section) != null) {
                std.log.info("✅ Found required section: {s}", .{section});
            } else {
                std.log.warn("⚠️  Missing section: {s}", .{section});
            }
        }
        
        // Check preset files
        const presets = [_][]const u8{ "performance", "debug", "minimal" };
        for (presets) |preset| {
            const preset_path = try std.fmt.allocPrint(self.allocator, "config/presets/{s}.toml", .{preset});
            defer self.allocator.free(preset_path);
            
            if (std.fs.cwd().access(preset_path, .{})) {
                std.log.info("✅ Preset available: {s}", .{preset});
            } else |_| {
                std.log.warn("⚠️  Preset missing: {s}", .{preset});
            }
        }
        
        if (errors == 0) {
            std.log.info("✅ Configuration validation passed");
        } else {
            std.log.err("❌ Configuration validation failed with {} errors", .{errors});
        }
    }
    
    fn validateTomlSyntax(self: *Self, content: []const u8) !bool {
        _ = self;
        
        // Very basic TOML validation
        var line_count: u32 = 0;
        var in_string = false;
        var bracket_count: i32 = 0;
        
        for (content) |char| {
            switch (char) {
                '"' => in_string = !in_string,
                '[' => if (!in_string) bracket_count += 1,
                ']' => if (!in_string) bracket_count -= 1,
                '\n' => line_count += 1,
                else => {},
            }
        }
        
        return bracket_count == 0 and !in_string;
    }
    
    fn listProfiles(self: *Self) !void {
        std.log.info("📋 Available Configuration Profiles");
        std.log.info("==================================");
        
        const preset_dir = std.fs.cwd().openDir("config/presets", .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                std.log.warn("No presets directory found");
                return;
            }
            return err;
        };
        defer preset_dir.close();
        
        var iterator = preset_dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".toml")) {
                const profile_name = entry.name[0 .. entry.name.len - 5]; // Remove .toml
                
                const profile_path = try std.fmt.allocPrint(self.allocator, "config/presets/{s}", .{entry.name});
                defer self.allocator.free(profile_path);
                
                const profile_content = std.fs.cwd().readFileAlloc(self.allocator, profile_path, 1000) catch |err| {
                    std.log.warn("Failed to read profile {s}: {}", .{ profile_name, err });
                    continue;
                };
                defer self.allocator.free(profile_content);
                
                std.log.info("📄 {s}", .{profile_name});
                
                // Extract description from first comment line
                var lines = std.mem.split(u8, profile_content, "\n");
                while (lines.next()) |line| {
                    const trimmed = std.mem.trim(u8, line, " \t");
                    if (trimmed.len > 0 and trimmed[0] == '#') {
                        std.log.info("   {s}", .{trimmed[1..]});
                        break;
                    } else if (trimmed.len > 0) {
                        break;
                    }
                }
                
                std.log.info("");
            }
        }
        
        // Show active profile
        try self.showActiveProfile();
    }
    
    fn applyProfile(self: *Self, profile_name: []const u8) !void {
        std.log.info("🔧 Applying profile: {s}", .{profile_name});
        
        const profile_path = try std.fmt.allocPrint(self.allocator, "config/presets/{s}.toml", .{profile_name});
        defer self.allocator.free(profile_path);
        
        // Check if profile exists
        std.fs.cwd().access(profile_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.log.err("Profile not found: {s}", .{profile_name});
                std.log.info("Available profiles:");
                try self.listProfiles();
                return;
            }
            return err;
        };
        
        // Read profile content
        const profile_content = try std.fs.cwd().readFileAlloc(self.allocator, profile_path, 10000);
        defer self.allocator.free(profile_content);
        
        // Write to main config file
        const config_file = try std.fs.cwd().createFile("config/zmin.toml", .{});
        defer config_file.close();
        
        try config_file.writeAll("# Applied profile: ");
        try config_file.writeAll(profile_name);
        try config_file.writeAll("\n# Generated by config-manager\n\n");
        try config_file.writeAll(profile_content);
        
        // Save active profile
        const active_profile_file = try std.fs.cwd().createFile("config/.active_profile", .{});
        defer active_profile_file.close();
        try active_profile_file.writeAll(profile_name);
        
        std.log.info("✅ Profile applied successfully");
        std.log.info("Configuration updated: config/zmin.toml");
    }
    
    fn setConfigValue(self: *Self, key: []const u8, value: []const u8) !void {
        std.log.info("🔧 Setting {s} = {s}", .{ key, value });
        
        // For now, just show what would be set
        // In a real implementation, you'd parse and modify the TOML file
        std.log.info("✅ Configuration value set (simulated)");
        std.log.info("Note: This is a simplified implementation");
        std.log.info("In practice, this would modify config/zmin.toml");
    }
    
    fn getConfigValue(self: *Self, key: []const u8) !void {
        _ = self;
        
        std.log.info("🔍 Getting value for: {s}", .{key});
        
        // For now, just show what would be retrieved
        // In a real implementation, you'd parse the TOML file
        std.log.info("Note: This is a simplified implementation");
        std.log.info("In practice, this would read from config/zmin.toml");
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
    
    var config_manager = ConfigManager.init(allocator);
    try config_manager.run(command_args);
}