const std = @import("std");
const plugin_interface = @import("plugin_interface");
const PluginInterface = plugin_interface.PluginInterface;
const PluginInfo = plugin_interface.PluginInfo;
const PluginType = plugin_interface.PluginType;

/// Custom JSON validator plugin with enhanced validation rules
const CustomValidatorPlugin = struct {
    allocator: std.mem.Allocator,
    config: Config,
    
    const Config = struct {
        strict_mode: bool = false,
        max_depth: u32 = 100,
        max_string_length: u32 = 10000,
        allow_comments: bool = false,
        allow_trailing_commas: bool = false,
    };
    
    const ValidationError = error{
        InvalidJson,
        MaxDepthExceeded,
        StringTooLong,
        UnexpectedCharacter,
        UnterminatedString,
        InvalidNumber,
        CommentsNotAllowed,
        TrailingCommaNotAllowed,
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
    
    pub fn validate(self: *Self, input: []const u8) ![]u8 {
        var parser = JsonValidator{
            .input = input,
            .pos = 0,
            .depth = 0,
            .config = &self.config,
        };
        
        try parser.parseValue();
        parser.skipWhitespace();
        
        if (parser.pos < input.len) {
            return ValidationError.UnexpectedCharacter;
        }
        
        // Return validation result as JSON
        return try std.fmt.allocPrint(self.allocator,
            \\{{"valid": true, "message": "JSON is valid", "details": {{"depth": {}, "length": {}}}}}
        , .{ parser.depth, input.len });
    }
    
    const JsonValidator = struct {
        input: []const u8,
        pos: usize,
        depth: u32,
        config: *const Config,
        
        fn parseValue(self: *@This()) !void {
            self.skipWhitespace();
            
            if (self.pos >= self.input.len) {
                return ValidationError.UnexpectedCharacter;
            }
            
            switch (self.input[self.pos]) {
                '"' => try self.parseString(),
                '{' => try self.parseObject(),
                '[' => try self.parseArray(),
                't', 'f' => try self.parseBoolean(),
                'n' => try self.parseNull(),
                '0'...'9', '-' => try self.parseNumber(),
                '/' => {
                    if (self.config.allow_comments) {
                        try self.parseComment();
                        try self.parseValue(); // Parse next value after comment
                    } else {
                        return ValidationError.CommentsNotAllowed;
                    }
                },
                else => return ValidationError.UnexpectedCharacter,
            }
        }
        
        fn parseString(self: *@This()) !void {
            self.pos += 1; // Skip opening quote
            var length: u32 = 0;
            var escaped = false;
            
            while (self.pos < self.input.len) {
                const char = self.input[self.pos];
                self.pos += 1;
                length += 1;
                
                if (length > self.config.max_string_length) {
                    return ValidationError.StringTooLong;
                }
                
                if (escaped) {
                    escaped = false;
                    continue;
                }
                
                if (char == '\\') {
                    escaped = true;
                } else if (char == '"') {
                    return; // End of string
                }
            }
            
            return ValidationError.UnterminatedString;
        }
        
        fn parseObject(self: *@This()) !void {
            self.depth += 1;
            if (self.depth > self.config.max_depth) {
                return ValidationError.MaxDepthExceeded;
            }
            
            self.pos += 1; // Skip opening brace
            self.skipWhitespace();
            
            if (self.pos < self.input.len and self.input[self.pos] == '}') {
                self.pos += 1;
                self.depth -= 1;
                return; // Empty object
            }
            
            while (true) {
                // Parse key
                if (self.pos >= self.input.len or self.input[self.pos] != '"') {
                    return ValidationError.UnexpectedCharacter;
                }
                try self.parseString();
                
                self.skipWhitespace();
                
                // Expect colon
                if (self.pos >= self.input.len or self.input[self.pos] != ':') {
                    return ValidationError.UnexpectedCharacter;
                }
                self.pos += 1;
                
                // Parse value
                try self.parseValue();
                self.skipWhitespace();
                
                if (self.pos >= self.input.len) {
                    return ValidationError.UnexpectedCharacter;
                }
                
                if (self.input[self.pos] == '}') {
                    self.pos += 1;
                    break;
                } else if (self.input[self.pos] == ',') {
                    self.pos += 1;
                    self.skipWhitespace();
                    
                    // Check for trailing comma
                    if (self.pos < self.input.len and self.input[self.pos] == '}') {
                        if (!self.config.allow_trailing_commas) {
                            return ValidationError.TrailingCommaNotAllowed;
                        }
                        self.pos += 1;
                        break;
                    }
                } else {
                    return ValidationError.UnexpectedCharacter;
                }
            }
            
            self.depth -= 1;
        }
        
        fn parseArray(self: *@This()) !void {
            self.depth += 1;
            if (self.depth > self.config.max_depth) {
                return ValidationError.MaxDepthExceeded;
            }
            
            self.pos += 1; // Skip opening bracket
            self.skipWhitespace();
            
            if (self.pos < self.input.len and self.input[self.pos] == ']') {
                self.pos += 1;
                self.depth -= 1;
                return; // Empty array
            }
            
            while (true) {
                try self.parseValue();
                self.skipWhitespace();
                
                if (self.pos >= self.input.len) {
                    return ValidationError.UnexpectedCharacter;
                }
                
                if (self.input[self.pos] == ']') {
                    self.pos += 1;
                    break;
                } else if (self.input[self.pos] == ',') {
                    self.pos += 1;
                    self.skipWhitespace();
                    
                    // Check for trailing comma
                    if (self.pos < self.input.len and self.input[self.pos] == ']') {
                        if (!self.config.allow_trailing_commas) {
                            return ValidationError.TrailingCommaNotAllowed;
                        }
                        self.pos += 1;
                        break;
                    }
                } else {
                    return ValidationError.UnexpectedCharacter;
                }
            }
            
            self.depth -= 1;
        }
        
        fn parseBoolean(self: *@This()) !void {
            if (self.pos + 4 <= self.input.len and std.mem.eql(u8, self.input[self.pos..self.pos + 4], "true")) {
                self.pos += 4;
            } else if (self.pos + 5 <= self.input.len and std.mem.eql(u8, self.input[self.pos..self.pos + 5], "false")) {
                self.pos += 5;
            } else {
                return ValidationError.UnexpectedCharacter;
            }
        }
        
        fn parseNull(self: *@This()) !void {
            if (self.pos + 4 <= self.input.len and std.mem.eql(u8, self.input[self.pos..self.pos + 4], "null")) {
                self.pos += 4;
            } else {
                return ValidationError.UnexpectedCharacter;
            }
        }
        
        fn parseNumber(self: *@This()) !void {
            const start = self.pos;
            
            // Optional minus sign
            if (self.pos < self.input.len and self.input[self.pos] == '-') {
                self.pos += 1;
            }
            
            // Integer part
            if (self.pos >= self.input.len or !std.ascii.isDigit(self.input[self.pos])) {
                return ValidationError.InvalidNumber;
            }
            
            if (self.input[self.pos] == '0') {
                self.pos += 1;
            } else {
                while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
                    self.pos += 1;
                }
            }
            
            // Optional fractional part
            if (self.pos < self.input.len and self.input[self.pos] == '.') {
                self.pos += 1;
                if (self.pos >= self.input.len or !std.ascii.isDigit(self.input[self.pos])) {
                    return ValidationError.InvalidNumber;
                }
                while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
                    self.pos += 1;
                }
            }
            
            // Optional exponent
            if (self.pos < self.input.len and (self.input[self.pos] == 'e' or self.input[self.pos] == 'E')) {
                self.pos += 1;
                if (self.pos < self.input.len and (self.input[self.pos] == '+' or self.input[self.pos] == '-')) {
                    self.pos += 1;
                }
                if (self.pos >= self.input.len or !std.ascii.isDigit(self.input[self.pos])) {
                    return ValidationError.InvalidNumber;
                }
                while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
                    self.pos += 1;
                }
            }
            
            if (self.pos == start) {
                return ValidationError.InvalidNumber;
            }
        }
        
        fn parseComment(self: *@This()) !void {
            if (self.pos + 1 >= self.input.len) {
                return ValidationError.UnexpectedCharacter;
            }
            
            if (self.input[self.pos + 1] == '/') {
                // Line comment
                self.pos += 2;
                while (self.pos < self.input.len and self.input[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else if (self.input[self.pos + 1] == '*') {
                // Block comment
                self.pos += 2;
                while (self.pos + 1 < self.input.len) {
                    if (self.input[self.pos] == '*' and self.input[self.pos + 1] == '/') {
                        self.pos += 2;
                        return;
                    }
                    self.pos += 1;
                }
                return ValidationError.UnexpectedCharacter; // Unterminated comment
            } else {
                return ValidationError.UnexpectedCharacter;
            }
        }
        
        fn skipWhitespace(self: *@This()) void {
            while (self.pos < self.input.len) {
                const char = self.input[self.pos];
                if (char == ' ' or char == '\t' or char == '\n' or char == '\r') {
                    self.pos += 1;
                } else {
                    break;
                }
            }
        }
    };
};

// Plugin instance
var plugin_instance: ?*CustomValidatorPlugin = null;

// Zig plugin interface
pub fn getPluginInterface() PluginInterface {
    return PluginInterface{
        .name = "custom_validator",
        .version = "1.0.0",
        .plugin_type = .validator,
        .api_version = plugin_interface.PLUGIN_API_VERSION,
        .init = zigInit,
        .deinit = zigDeinit,
        .get_info = zigGetInfo,
        .process = zigProcess,
        .validate_config = zigValidateConfig,
    };
}

fn zigInit(allocator: std.mem.Allocator) anyerror!*anyopaque {
    const plugin = try CustomValidatorPlugin.init(allocator);
    return @as(*anyopaque, @ptrCast(plugin));
}

fn zigDeinit(instance: *anyopaque) void {
    const plugin = @as(*CustomValidatorPlugin, @ptrCast(@alignCast(instance)));
    plugin.deinit();
}

fn zigGetInfo() PluginInfo {
    return PluginInfo{
        .name = "Custom Validator",
        .version = "1.0.0",
        .description = "Enhanced JSON validator with configurable rules",
        .author = "zmin Team",
        .license = "MIT",
        .plugin_type = .validator,
        .api_version = plugin_interface.PLUGIN_API_VERSION,
        .capabilities = &[_][]const u8{ "strict_validation", "depth_checking", "comment_support", "trailing_comma_support" },
        .dependencies = &[_][]const u8{},
    };
}

fn zigProcess(instance: *anyopaque, input: []const u8, allocator: std.mem.Allocator) anyerror![]u8 {
    _ = allocator;
    const plugin = @as(*CustomValidatorPlugin, @ptrCast(@alignCast(instance)));
    return plugin.validate(input);
}

fn zigValidateConfig(config: []const u8) bool {
    _ = config;
    // Basic validation - could parse TOML/JSON config here
    return true;
}