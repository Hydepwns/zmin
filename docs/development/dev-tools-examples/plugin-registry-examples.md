# Plugin Registry Examples

The plugin-registry tool manages discovery, loading, and testing of zmin plugins for extended functionality.

## Basic Usage

### Plugin Discovery

```bash
# Discover plugins in standard locations
plugin-registry discover

# List all discovered plugins
plugin-registry list

# Show detailed information about a specific plugin
plugin-registry info 0
```

### Plugin Management

```bash
# Load all discovered plugins
plugin-registry load

# Test all loaded plugins
plugin-registry test

# Benchmark plugin performance
plugin-registry benchmark
```

## Advanced Examples

### Plugin Development Workflow

```bash
#!/bin/bash
# plugin-dev-workflow.sh

echo "🔌 Plugin Development Workflow"

# 1. Discover existing plugins
echo "1. Discovering existing plugins..."
plugin-registry discover

# 2. List available plugins
echo "2. Available plugins:"
plugin-registry list

# 3. Load plugins for testing
echo "3. Loading plugins..."
plugin-registry load

# 4. Test plugin functionality
echo "4. Testing plugins..."
plugin-registry test

# 5. Benchmark performance
echo "5. Benchmarking plugin performance..."
plugin-registry benchmark
```

### Custom Plugin Creation

```zig
// example-plugin/src/minifier_plugin.zig
const std = @import("std");
const plugin_interface = @import("plugin_interface");

pub const MinifierPlugin = struct {
    const Self = @This();
    
    pub fn getName() []const u8 {
        return "example-minifier";
    }
    
    pub fn getVersion() []const u8 {
        return "1.0.0";
    }
    
    pub fn getDescription() []const u8 {
        return "Example JSON minifier plugin";
    }
    
    pub fn getCapabilities() []const []const u8 {
        return &[_][]const u8{"minify", "validate"};
    }
    
    pub fn minify(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
        // Custom minification logic
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        // Simple whitespace removal example
        for (input) |char| {
            switch (char) {
                ' ', '\t', '\n', '\r' => {
                    // Skip whitespace outside of strings
                    continue;
                },
                else => {
                    try result.append(char);
                },
            }
        }
        
        return try result.toOwnedSlice();
    }
};

// Plugin export
pub export fn createPlugin() *plugin_interface.Plugin {
    return &MinifierPlugin{};
}
```

### Plugin Configuration

```json
{
  "plugin_registry": {
    "search_paths": [
      "/usr/local/lib/zmin/plugins",
      "/opt/zmin/plugins", 
      "./plugins",
      "~/.zmin/plugins"
    ],
    "auto_discover": true,
    "enabled_plugins": [
      "fast-minifier",
      "validator-plugin",
      "custom-formatter"
    ],
    "disabled_plugins": [
      "experimental-plugin"
    ],
    "plugin_settings": {
      "fast-minifier": {
        "aggressive_mode": true,
        "preserve_formatting": false
      },
      "validator-plugin": {
        "strict_mode": true,
        "error_on_warnings": false
      }
    }
  }
}
```

## Plugin Development Examples

### Build Script for Plugins

```bash
#!/bin/bash
# build-plugin.sh

PLUGIN_NAME="$1"

if [ -z "$PLUGIN_NAME" ]; then
    echo "Usage: $0 <plugin-name>"
    exit 1
fi

echo "Building plugin: $PLUGIN_NAME"

# Create plugin directory structure
mkdir -p "plugins/$PLUGIN_NAME/src"
cd "plugins/$PLUGIN_NAME"

# Create build.zig for plugin
cat > build.zig << 'EOF'
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const plugin = b.addSharedLibrary(.{
        .name = "plugin",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(plugin);
}
EOF

# Create plugin manifest
cat > plugin.json << EOF
{
  "name": "$PLUGIN_NAME",
  "version": "1.0.0",
  "description": "Custom plugin for zmin",
  "author": "Developer",
  "license": "MIT",
  "api_version": "1.0.0",
  "capabilities": ["minify"],
  "dependencies": [],
  "entry_point": "zig-out/lib/libplugin.so"
}
EOF

# Build the plugin
zig build

echo "✅ Plugin $PLUGIN_NAME built successfully"
echo "Plugin location: $(pwd)/zig-out/lib/"
```

### Plugin Testing Framework

```bash
#!/bin/bash
# test-plugin.sh

PLUGIN_PATH="$1"

if [ -z "$PLUGIN_PATH" ]; then
    echo "Usage: $0 <plugin-path>"
    exit 1
fi

echo "Testing plugin: $PLUGIN_PATH"

# Test data
TEST_CASES=(
    '{"simple": "test"}'
    '{"complex": {"nested": [1, 2, 3]}}'
    '{"large": "'$(printf 'A%.0s' {1..1000})'"}'
)

echo "Running plugin tests..."

for i in "${!TEST_CASES[@]}"; do
    test_case="${TEST_CASES[$i]}"
    echo "Test case $((i+1)): $(echo "$test_case" | cut -c1-50)..."
    
    # Save test case to file
    echo "$test_case" > "test_input_$i.json"
    
    # Test with plugin registry
    if plugin-registry test --plugin "$PLUGIN_PATH" --input "test_input_$i.json"; then
        echo "✅ Test case $((i+1)) passed"
    else
        echo "❌ Test case $((i+1)) failed"
    fi
    
    rm "test_input_$i.json"
done

echo "Plugin testing completed"
```

## Integration Examples

### Plugin Packaging

```bash
#!/bin/bash
# package-plugin.sh

PLUGIN_NAME="$1"
VERSION="$2"

if [ -z "$PLUGIN_NAME" ] || [ -z "$VERSION" ]; then
    echo "Usage: $0 <plugin-name> <version>"
    exit 1
fi

echo "Packaging plugin: $PLUGIN_NAME v$VERSION"

PACKAGE_DIR="dist/$PLUGIN_NAME-$VERSION"
mkdir -p "$PACKAGE_DIR"

# Copy plugin files
cp "plugins/$PLUGIN_NAME/zig-out/lib/"* "$PACKAGE_DIR/"
cp "plugins/$PLUGIN_NAME/plugin.json" "$PACKAGE_DIR/"
cp "plugins/$PLUGIN_NAME/README.md" "$PACKAGE_DIR/" 2>/dev/null || true

# Create installation script
cat > "$PACKAGE_DIR/install.sh" << 'EOF'
#!/bin/bash

PLUGIN_DIR="$HOME/.zmin/plugins"
mkdir -p "$PLUGIN_DIR"

echo "Installing plugin to $PLUGIN_DIR..."
cp *.so "$PLUGIN_DIR/" 2>/dev/null || cp *.dll "$PLUGIN_DIR/" 2>/dev/null || cp *.dylib "$PLUGIN_DIR/"
cp plugin.json "$PLUGIN_DIR/"

echo "✅ Plugin installed successfully"
echo "Run 'plugin-registry discover' to detect the new plugin"
EOF

chmod +x "$PACKAGE_DIR/install.sh"

# Create archive
tar -czf "dist/$PLUGIN_NAME-$VERSION.tar.gz" -C dist "$PLUGIN_NAME-$VERSION"

echo "✅ Plugin packaged: dist/$PLUGIN_NAME-$VERSION.tar.gz"
```

### Plugin CI/CD Pipeline

```yaml
# .github/workflows/plugin-ci.yml
name: Plugin CI

on:
  push:
    paths:
      - 'plugins/**'
  pull_request:
    paths:
      - 'plugins/**'

jobs:
  test-plugins:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Zig
      uses: goto-bus-stop/setup-zig@v2
      with:
        version: 0.13.0
    
    - name: Build main project
      run: zig build tools
    
    - name: Discover and test plugins
      run: |
        # Build any plugins in the repository
        for plugin_dir in plugins/*/; do
          if [ -f "$plugin_dir/build.zig" ]; then
            echo "Building plugin in $plugin_dir"
            cd "$plugin_dir"
            zig build
            cd - > /dev/null
          fi
        done
        
        # Test plugins
        ./zig-out/bin/plugin-registry discover
        ./zig-out/bin/plugin-registry load
        ./zig-out/bin/plugin-registry test
    
    - name: Benchmark plugins
      run: |
        ./zig-out/bin/plugin-registry benchmark
```

## Plugin Management Scripts

### Plugin Discovery and Installation

```bash
#!/bin/bash
# manage-plugins.sh

COMMAND="$1"

case "$COMMAND" in
    "install")
        PLUGIN_URL="$2"
        if [ -z "$PLUGIN_URL" ]; then
            echo "Usage: $0 install <plugin-url>"
            exit 1
        fi
        
        echo "Installing plugin from $PLUGIN_URL..."
        
        # Download and extract plugin
        curl -L "$PLUGIN_URL" | tar -xz -C /tmp/
        
        # Find and install plugin
        PLUGIN_DIR=$(find /tmp -name "plugin.json" -exec dirname {} \; | head -1)
        if [ -n "$PLUGIN_DIR" ]; then
            cd "$PLUGIN_DIR"
            ./install.sh
            echo "✅ Plugin installed"
        else
            echo "❌ Invalid plugin package"
            exit 1
        fi
        ;;
        
    "remove")
        PLUGIN_NAME="$2"
        if [ -z "$PLUGIN_NAME" ]; then
            echo "Usage: $0 remove <plugin-name>"
            exit 1
        fi
        
        echo "Removing plugin: $PLUGIN_NAME"
        
        # Remove plugin files
        rm -f "$HOME/.zmin/plugins/$PLUGIN_NAME"*
        
        echo "✅ Plugin removed"
        ;;
        
    "update")
        echo "Updating all plugins..."
        
        # Re-discover plugins
        plugin-registry discover
        plugin-registry load
        
        echo "✅ Plugins updated"
        ;;
        
    "list")
        echo "Available plugins:"
        plugin-registry list
        ;;
        
    *)
        echo "Usage: $0 {install|remove|update|list}"
        echo ""
        echo "Commands:" 
        echo "  install <url>   - Install plugin from URL"
        echo "  remove <name>   - Remove installed plugin"
        echo "  update          - Update plugin registry"
        echo "  list            - List available plugins"
        exit 1
        ;;
esac
```

### Plugin Development Helper

```bash
#!/bin/bash
# plugin-dev-helper.sh

create_plugin() {
    local name="$1"
    local description="$2"
    
    echo "Creating plugin: $name"
    
    mkdir -p "plugins/$name/src"
    cd "plugins/$name"
    
    # Create main plugin file
    cat > "src/main.zig" << EOF
const std = @import("std");

pub const Plugin = struct {
    pub fn getName() []const u8 {
        return "$name";
    }
    
    pub fn getVersion() []const u8 {
        return "1.0.0";
    }
    
    pub fn getDescription() []const u8 {
        return "$description";
    }
    
    pub fn minify(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
        // TODO: Implement minification logic
        return try allocator.dupe(u8, input);
    }
};

pub export fn createPlugin() *Plugin {
    return &Plugin{};
}
EOF
    
    # Create build.zig
    cat > "build.zig" << 'EOF'
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const plugin = b.addSharedLibrary(.{
        .name = "plugin",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(plugin);
}
EOF
    
    # Create plugin manifest
    cat > "plugin.json" << EOF
{
  "name": "$name",
  "version": "1.0.0", 
  "description": "$description",
  "author": "$(whoami)",
  "license": "MIT",
  "api_version": "1.0.0",
  "capabilities": ["minify"],
  "dependencies": []
}
EOF
    
    echo "✅ Plugin template created in plugins/$name/"
    echo "Edit src/main.zig to implement your plugin logic"
}

build_plugin() {
    local name="$1"
    
    if [ ! -d "plugins/$name" ]; then
        echo "❌ Plugin $name not found"
        exit 1
    fi
    
    echo "Building plugin: $name"
    cd "plugins/$name"
    zig build
    echo "✅ Plugin built"
}

test_plugin() {
    local name="$1"
    
    echo "Testing plugin: $name"
    
    # Build if needed
    if [ ! -f "plugins/$name/zig-out/lib/"* ]; then
        build_plugin "$name"
    fi
    
    # Test with plugin registry
    plugin-registry discover
    plugin-registry load
    plugin-registry test
}

case "$1" in
    "create")
        create_plugin "$2" "$3"
        ;;
    "build")
        build_plugin "$2"
        ;;
    "test")
        test_plugin "$2"
        ;;
    *)
        echo "Usage: $0 {create|build|test} <plugin-name> [description]"
        exit 1
        ;;
esac
```

## Best Practices

1. **Plugin Isolation**: Keep plugins in separate directories with clear dependencies
2. **Version Management**: Use semantic versioning for plugins
3. **Testing**: Thoroughly test plugins with various input types
4. **Documentation**: Document plugin capabilities and usage
5. **Error Handling**: Implement robust error handling in plugins
6. **Performance**: Benchmark plugin performance regularly
7. **Security**: Validate plugin sources and permissions
8. **Compatibility**: Ensure plugins work with different zmin versions