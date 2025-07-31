const std = @import("std");

/// Common test fixtures for dev tools testing
pub const DevToolsFixtures = struct {
    /// Sample configuration files for testing
    pub const ConfigFixtures = struct {
        /// Basic valid configuration
        pub const basic_config =
            \\{
            \\  "dev_server": {
            \\    "port": 8080,
            \\    "host": "localhost",
            \\    "enable_cors": true,
            \\    "log_requests": true
            \\  },
            \\  "debugger": {
            \\    "port": 9229,
            \\    "enable_inspector": true,
            \\    "break_on_start": false,
            \\    "log_level": "info"
            \\  },
            \\  "profiler": {
            \\    "output_dir": "/tmp/zmin-profiles",
            \\    "sample_rate": 1000,
            \\    "enable_memory_tracking": true,
            \\    "max_profile_size_mb": 50
            \\  },
            \\  "hot_reloading": {
            \\    "watch_patterns": ["*.zig", "*.json", "*.toml"],
            \\    "ignore_patterns": ["target/**", "zig-out/**", ".git/**"],
            \\    "debounce_ms": 500,
            \\    "enable_notifications": false
            \\  },
            \\  "plugin_registry": {
            \\    "search_paths": [
            \\      "/usr/local/lib/zmin/plugins",
            \\      "./plugins",
            \\      "~/.zmin/plugins"
            \\    ],
            \\    "enabled_plugins": ["default-minifier", "performance-monitor"],
            \\    "disabled_plugins": ["experimental-plugin"],
            \\    "auto_discovery": true
            \\  }
            \\}
        ;

        /// Configuration with invalid values
        pub const invalid_config =
            \\{
            \\  "dev_server": {
            \\    "port": "not-a-number",
            \\    "host": "",
            \\    "enable_cors": "maybe"
            \\  },
            \\  "debugger": {
            \\    "port": -1,
            \\    "log_level": "invalid"
            \\  },
            \\  "profiler": {
            \\    "sample_rate": "fast",
            \\    "max_profile_size_mb": -10
            \\  }
            \\}
        ;

        /// Minimal valid configuration
        pub const minimal_config =
            \\{
            \\  "dev_server": {
            \\    "port": 3000
            \\  }
            \\}
        ;

        /// Production-style configuration
        pub const production_config =
            \\{
            \\  "dev_server": {
            \\    "port": 80,
            \\    "host": "0.0.0.0",
            \\    "enable_cors": false,
            \\    "log_requests": false,
            \\    "enable_ssl": true,
            \\    "ssl_cert": "/etc/ssl/certs/zmin.crt",
            \\    "ssl_key": "/etc/ssl/private/zmin.key"
            \\  },
            \\  "debugger": {
            \\    "port": 9229,
            \\    "enable_inspector": false,
            \\    "break_on_start": false,
            \\    "log_level": "error"
            \\  },
            \\  "profiler": {
            \\    "output_dir": "/var/log/zmin/profiles",
            \\    "sample_rate": 100,
            \\    "enable_memory_tracking": false,
            \\    "max_profile_size_mb": 100,
            \\    "compression": "gzip"
            \\  },
            \\  "hot_reloading": {
            \\    "enabled": false
            \\  },
            \\  "plugin_registry": {
            \\    "search_paths": ["/opt/zmin/plugins"],
            \\    "enabled_plugins": ["production-minifier", "security-validator"],
            \\    "auto_discovery": false,
            \\    "security_mode": "strict"
            \\  }
            \\}
        ;
    };

    /// Sample JSON files for testing minification
    pub const JsonFixtures = struct {
        /// Simple object
        pub const simple_object =
            \\{
            \\  "name": "test",
            \\  "value": 42,
            \\  "enabled": true
            \\}
        ;

        /// Complex nested structure
        pub const complex_nested =
            \\{
            \\  "metadata": {
            \\    "version": "1.0.0",
            \\    "created": "2023-12-01T10:00:00Z",
            \\    "author": {
            \\      "name": "Test User",
            \\      "email": "test@example.com",
            \\      "roles": ["admin", "developer"]
            \\    }
            \\  },
            \\  "data": {
            \\    "items": [
            \\      {
            \\        "id": 1,
            \\        "type": "document",
            \\        "properties": {
            \\          "title": "Sample Document",
            \\          "tags": ["important", "review"],
            \\          "metrics": {
            \\            "views": 1250,
            \\            "likes": 89,
            \\            "shares": 12
            \\          }
            \\        }
            \\      },
            \\      {
            \\        "id": 2,
            \\        "type": "image",
            \\        "properties": {
            \\          "filename": "screenshot.png",
            \\          "size": 2048576,
            \\          "dimensions": {
            \\            "width": 1920,
            \\            "height": 1080
            \\          }
            \\        }
            \\      }
            \\    ]
            \\  }
            \\}
        ;

        /// Array with mixed types
        pub const mixed_array =
            \\[
            \\  null,
            \\  true,
            \\  false,
            \\  42,
            \\  -17.5,
            \\  1.23e-10,
            \\  "string value",
            \\  "string with \"quotes\" and \\n newlines",
            \\  {},
            \\  [],
            \\  {
            \\    "nested": {
            \\      "deeply": {
            \\        "nested": "value"
            \\      }
            \\    }
            \\  },
            \\  [1, [2, [3, [4, 5]]]]
            \\]
        ;

        /// Large array for performance testing
        pub fn generateLargeArray(allocator: std.mem.Allocator, size: usize) ![]u8 {
            var json = std.ArrayList(u8).init(allocator);
            try json.appendSlice("[");

            for (0..size) |i| {
                if (i > 0) try json.appendSlice(",");
                const item = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"value\":\"item-{d}\"}}", .{ i, i });
                defer allocator.free(item);
                try json.appendSlice(item);
            }

            try json.appendSlice("]");
            return json.toOwnedSlice();
        }
    };

    /// Sample plugin configurations
    pub const PluginFixtures = struct {
        /// Basic plugin manifest
        pub const plugin_manifest =
            \\{
            \\  "name": "test-plugin",
            \\  "version": "1.0.0",
            \\  "description": "Test plugin for integration testing",
            \\  "author": "Test Author",
            \\  "entry_point": "lib/test_plugin.so",
            \\  "capabilities": [
            \\    "minification",
            \\    "validation"
            \\  ],
            \\  "dependencies": {
            \\    "zmin": ">=1.0.0"
            \\  },
            \\  "configuration": {
            \\    "enable_optimization": true,
            \\    "max_file_size_mb": 10,
            \\    "supported_formats": ["json", "jsonl"]
            \\  }
            \\}
        ;

        /// Plugin with complex configuration
        pub const complex_plugin_manifest =
            \\{
            \\  "name": "advanced-minifier",
            \\  "version": "2.1.3",
            \\  "description": "Advanced JSON minifier with custom algorithms",
            \\  "author": "Advanced Dev Team",
            \\  "license": "MIT",
            \\  "entry_point": "bin/advanced_minifier",
            \\  "capabilities": [
            \\    "minification",
            \\    "validation",
            \\    "optimization",
            \\    "metrics"
            \\  ],
            \\  "dependencies": {
            \\    "zmin": ">=1.0.0",
            \\    "liboptimizer": ">=3.2.0"
            \\  },
            \\  "configuration": {
            \\    "algorithms": {
            \\      "default": "turbo-v3",
            \\      "fallback": "standard",
            \\      "options": {
            \\        "preserve_order": false,
            \\        "optimize_numbers": true,
            \\        "compress_strings": true
            \\      }
            \\    },
            \\    "performance": {
            \\      "max_memory_mb": 512,
            \\      "thread_pool_size": 4,
            \\      "chunk_size_kb": 64
            \\    },
            \\    "validation": {
            \\      "strict_mode": false,
            \\      "allow_comments": false,
            \\      "max_depth": 1000
            \\    }
            \\  },
            \\  "platform": {
            \\    "os": ["linux", "macos", "windows"],
            \\    "arch": ["x86_64", "aarch64"]
            \\  }
            \\}
        ;
    };

    /// Error scenarios for testing
    pub const ErrorFixtures = struct {
        /// Common error messages
        pub const file_not_found = "The specified file could not be found";
        pub const invalid_json = "Invalid JSON syntax at line 5, column 12";
        pub const permission_denied = "Permission denied accessing configuration file";
        pub const out_of_memory = "Insufficient memory to complete operation";
        pub const network_timeout = "Network request timed out after 30 seconds";

        /// Invalid JSON strings
        pub const invalid_json_samples = [_][]const u8{
            "{", // Incomplete object
            "{ \"key\": }", // Missing value
            "{ \"key\": \"value\" ", // Missing closing brace
            "{ \"key\" \"value\" }", // Missing colon
            "{ key: \"value\" }", // Unquoted key
            "{ \"key\": 'value' }", // Single quotes
            "{ \"key\": undefined }", // Undefined value
            "{ \"key\": +123 }", // Invalid number format
            "{ \"key\": 123. }", // Invalid decimal
            "{ \"key\": \"val\\ue\" }", // Invalid escape
        };

        /// Large invalid structures
        pub fn generateInvalidLargeJson(allocator: std.mem.Allocator) ![]u8 {
            var json = std.ArrayList(u8).init(allocator);

            // Start valid structure
            try json.appendSlice("{\"data\":[");

            // Add many valid items
            for (0..100) |i| {
                if (i > 0) try json.appendSlice(",");
                const item = try std.fmt.allocPrint(allocator, "{{\"id\":{d}}}", .{i});
                defer allocator.free(item);
                try json.appendSlice(item);
            }

            // Add invalid item at the end
            try json.appendSlice(",{\"id\":101,\"invalid\":}");

            // Don't close properly (missing ]}
            return json.toOwnedSlice();
        }
    };

    /// Performance test scenarios
    pub const PerformanceFixtures = struct {
        /// Configuration for performance testing
        pub const perf_config =
            \\{
            \\  "profiler": {
            \\    "sample_rate": 10000,
            \\    "enable_memory_tracking": true,
            \\    "enable_cpu_profiling": true,
            \\    "output_format": "json",
            \\    "compression": "none"
            \\  },
            \\  "test_parameters": {
            \\    "warmup_iterations": 100,
            \\    "test_iterations": 1000,
            \\    "max_runtime_seconds": 30,
            \\    "memory_limit_mb": 256
            \\  }
            \\}
        ;

        /// Generate performance test data
        pub fn generatePerfTestData(allocator: std.mem.Allocator, complexity: enum { simple, medium, complex }) ![]u8 {
            return switch (complexity) {
                .simple => try std.fmt.allocPrint(allocator, "{{\"test\": \"simple\", \"value\": {d}}}", .{std.time.timestamp()}),

                .medium => blk: {
                    var json = std.ArrayList(u8).init(allocator);
                    try json.appendSlice("{\"test\": \"medium\", \"data\": [");
                    for (0..50) |i| {
                        if (i > 0) try json.appendSlice(",");
                        const item = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"name\":\"item-{d}\"}}", .{ i, i });
                        defer allocator.free(item);
                        try json.appendSlice(item);
                    }
                    try json.appendSlice("]}");
                    break :blk json.toOwnedSlice();
                },

                .complex => blk: {
                    var json = std.ArrayList(u8).init(allocator);
                    try json.appendSlice("{\"test\": \"complex\", \"nested\": {");
                    for (0..10) |i| {
                        if (i > 0) try json.appendSlice(",");
                        const section = try std.fmt.allocPrint(allocator, "\"section-{d}\": {{\"items\": [", .{i});
                        defer allocator.free(section);
                        try json.appendSlice(section);

                        for (0..20) |j| {
                            if (j > 0) try json.appendSlice(",");
                            const item = try std.fmt.allocPrint(allocator, "{{\"id\":{d},\"data\":\"content-{d}-{d}\"}}", .{ j, i, j });
                            defer allocator.free(item);
                            try json.appendSlice(item);
                        }
                        try json.appendSlice("]}");
                    }
                    try json.appendSlice("}}");
                    break :blk json.toOwnedSlice();
                },
            };
        }
    };

    /// Helper functions for creating test environments
    pub const TestHelpers = struct {
        /// Create a temporary directory with test files
        pub fn createTestDirectory(allocator: std.mem.Allocator, temp_dir: *std.testing.TmpDir) ![]const u8 {
            const temp_path = try temp_dir.dir.realpathAlloc(allocator, ".");

            // Create subdirectories
            try temp_dir.dir.makeDir("configs");
            try temp_dir.dir.makeDir("plugins");
            try temp_dir.dir.makeDir("profiles");
            try temp_dir.dir.makeDir("logs");

            // Write sample files
            try temp_dir.dir.writeFile("configs/basic.json", ConfigFixtures.basic_config);
            try temp_dir.dir.writeFile("configs/invalid.json", ConfigFixtures.invalid_config);
            try temp_dir.dir.writeFile("configs/minimal.json", ConfigFixtures.minimal_config);
            try temp_dir.dir.writeFile("plugins/manifest.json", PluginFixtures.plugin_manifest);

            // Create sample JSON files
            try temp_dir.dir.writeFile("test-simple.json", JsonFixtures.simple_object);
            try temp_dir.dir.writeFile("test-complex.json", JsonFixtures.complex_nested);
            try temp_dir.dir.writeFile("test-array.json", JsonFixtures.mixed_array);

            return temp_path;
        }

        /// Clean up test environment
        pub fn cleanupTestDirectory(allocator: std.mem.Allocator, path: []const u8) void {
            allocator.free(path);
        }

        /// Create mock error scenario
        pub fn createErrorScenario(allocator: std.mem.Allocator, scenario_type: enum { file_not_found, permission_denied, invalid_json, out_of_memory }) ![]const u8 {
            return switch (scenario_type) {
                .file_not_found => try allocator.dupe(u8, "/nonexistent/path/file.json"),
                .permission_denied => try allocator.dupe(u8, "/root/restricted.json"),
                .invalid_json => try allocator.dupe(u8, ErrorFixtures.invalid_json_samples[0]),
                .out_of_memory => try ErrorFixtures.generateInvalidLargeJson(allocator),
            };
        }
    };
};
