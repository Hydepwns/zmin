#!/bin/bash
# Package dev tools for distribution
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGE_DIR="$PROJECT_ROOT/dist"
VERSION=$(grep -Po '(?<="zmin": ")[^"]*' "$PROJECT_ROOT/.github/versions.json" || echo "dev")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

error() {
    echo -e "${RED}❌${NC} $1" >&2
}

# Platform detection
detect_platform() {
    case "$(uname -s)" in
        Linux*)     echo "linux";;
        Darwin*)    echo "macos";;
        CYGWIN*|MINGW*|MSYS*) echo "windows";;
        *)          echo "unknown";;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64";;
        aarch64|arm64) echo "aarch64";;
        arm*) echo "arm";;
        *) echo "unknown";;
    esac
}

PLATFORM=$(detect_platform)
ARCH=$(detect_arch)

log "🚀 Packaging zmin dev tools v$VERSION for $PLATFORM-$ARCH"

# Clean and create package directory
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

# Build dev tools
log "Building dev tools..."
cd "$PROJECT_ROOT"

if ! zig build tools --release=fast; then
    error "Failed to build dev tools"
    exit 1
fi

success "Dev tools built successfully"

# Create package structure
PACKAGE_NAME="zmin-dev-tools-$VERSION-$PLATFORM-$ARCH"
PACKAGE_PATH="$PACKAGE_DIR/$PACKAGE_NAME"

mkdir -p "$PACKAGE_PATH"/{bin,docs,examples,scripts}

# Copy binaries
log "Copying binaries..."
DEV_TOOLS=(
    "config-manager"
    "hot-reloading" 
    "dev-server"
    "profiler"
    "debugger"
    "plugin-registry"
)

for tool in "${DEV_TOOLS[@]}"; do
    if [ -f "zig-out/bin/$tool" ]; then
        cp "zig-out/bin/$tool" "$PACKAGE_PATH/bin/"
        success "Copied $tool"
    else
        warn "Tool $tool not found, skipping"
    fi
done

# Copy main zmin binary as well
if [ -f "zig-out/bin/zmin" ]; then
    cp "zig-out/bin/zmin" "$PACKAGE_PATH/bin/"
    success "Copied main zmin binary"
fi

# Copy documentation
log "Copying documentation..."
if [ -f "README.md" ]; then
    cp "README.md" "$PACKAGE_PATH/docs/"
fi

if [ -f "CHANGELOG.md" ]; then
    cp "CHANGELOG.md" "$PACKAGE_PATH/docs/"
fi

if [ -f "LICENSE" ]; then
    cp "LICENSE" "$PACKAGE_PATH/"
fi

# Copy tool-specific documentation
mkdir -p "$PACKAGE_PATH/docs/tools"
for tool in "${DEV_TOOLS[@]}"; do
    if [ -f "tools/docs/$tool.md" ]; then
        cp "tools/docs/$tool.md" "$PACKAGE_PATH/docs/tools/"
    fi
done

# Copy examples
log "Copying examples..."
if [ -d "tools/examples" ]; then
    cp -r tools/examples/* "$PACKAGE_PATH/examples/" 2>/dev/null || true
fi

# Create tool usage examples
cat > "$PACKAGE_PATH/examples/dev-workflow.sh" << 'EOF'
#!/bin/bash
# Example development workflow using zmin dev tools

echo "🔧 zmin Development Tools Workflow Example"
echo "=========================================="

# 1. Start development server
echo "Starting development server..."
./bin/dev-server 8080 &
SERVER_PID=$!
sleep 2

# 2. Test with debugger
echo "Running debugger analysis..."
echo '{"example": {"data": [1,2,3], "nested": {"key": "value"}}}' > example.json
./bin/debugger -i example.json -m sport --benchmark 10

# 3. Discover plugins
echo "Discovering available plugins..."
./bin/plugin-registry discover

# 4. Profile performance
echo "Running performance profiler..."
./bin/profiler --input example.json --modes eco,sport,turbo

# 5. Check configuration
echo "Managing configuration..."
./bin/config-manager --show-config

# Cleanup
kill $SERVER_PID 2>/dev/null || true
rm -f example.json

echo "✅ Workflow complete!"
EOF

chmod +x "$PACKAGE_PATH/examples/dev-workflow.sh"

# Create configuration templates
mkdir -p "$PACKAGE_PATH/examples/configs"

cat > "$PACKAGE_PATH/examples/configs/zmin.config.json" << 'EOF'
{
  "dev_server": {
    "port": 8080,
    "host": "localhost",
    "enable_debugging": true,
    "log_requests": true
  },
  "debugger": {
    "debug_level": "basic",
    "enable_profiling": true,
    "enable_memory_tracking": true,
    "benchmark_iterations": 10
  },
  "profiler": {
    "output_dir": "./profiles",
    "sample_rate": 1000,
    "enable_cpu_profiling": true,
    "enable_memory_profiling": true
  },
  "plugin_registry": {
    "search_paths": [
      "/usr/local/lib/zmin/plugins",
      "./plugins",
      "~/.zmin/plugins"
    ],
    "auto_discover": true,
    "enabled_plugins": []
  },
  "hot_reloading": {
    "watch_patterns": ["*.json", "*.zig"],
    "debounce_ms": 500,
    "ignore_patterns": [".git", "node_modules", "zig-out"]
  }
}
EOF

# Copy utility scripts
log "Copying utility scripts..."
cp -r scripts/* "$PACKAGE_PATH/scripts/" 2>/dev/null || true

# Create installation script
cat > "$PACKAGE_PATH/install.sh" << 'EOF'
#!/bin/bash
# Install zmin dev tools

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
INSTALL_DIR="$PREFIX/bin"
DOC_DIR="$PREFIX/share/doc/zmin-dev-tools"

echo "Installing zmin dev tools to $PREFIX..."

# Create directories
sudo mkdir -p "$INSTALL_DIR" "$DOC_DIR"

# Install binaries
echo "Installing binaries..."
sudo cp bin/* "$INSTALL_DIR/"

# Install documentation
echo "Installing documentation..."
sudo cp -r docs/* "$DOC_DIR/"

# Install examples
sudo mkdir -p "$DOC_DIR/examples"
sudo cp -r examples/* "$DOC_DIR/examples/"

echo "✅ Installation complete!"
echo ""
echo "Available commands:"
echo "  zmin              - Main JSON minifier"
echo "  config-manager    - Configuration management"
echo "  dev-server        - Development server"
echo "  debugger          - Performance debugger"
echo "  profiler          - Performance profiler"
echo "  plugin-registry   - Plugin management"
echo "  hot-reloading     - File watcher"
echo ""
echo "Documentation: $DOC_DIR"
echo "Examples: $DOC_DIR/examples"
EOF

chmod +x "$PACKAGE_PATH/install.sh"

# Create uninstallation script
cat > "$PACKAGE_PATH/uninstall.sh" << 'EOF'
#!/bin/bash
# Uninstall zmin dev tools

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
INSTALL_DIR="$PREFIX/bin"
DOC_DIR="$PREFIX/share/doc/zmin-dev-tools"

echo "Uninstalling zmin dev tools from $PREFIX..."

# Remove binaries
echo "Removing binaries..."
sudo rm -f "$INSTALL_DIR/zmin"
sudo rm -f "$INSTALL_DIR/config-manager"
sudo rm -f "$INSTALL_DIR/dev-server"
sudo rm -f "$INSTALL_DIR/debugger"
sudo rm -f "$INSTALL_DIR/profiler"
sudo rm -f "$INSTALL_DIR/plugin-registry"
sudo rm -f "$INSTALL_DIR/hot-reloading"

# Remove documentation
echo "Removing documentation..."
sudo rm -rf "$DOC_DIR"

echo "✅ Uninstallation complete!"
EOF

chmod +x "$PACKAGE_PATH/uninstall.sh"

# Create README for the package
cat > "$PACKAGE_PATH/README.md" << EOF
# zmin Development Tools v$VERSION

This package contains the complete zmin development toolkit for JSON minification and optimization.

## Contents

- **bin/**: Executable tools
- **docs/**: Documentation
- **examples/**: Usage examples and configuration templates
- **scripts/**: Utility scripts

## Installation

### Quick Install
\`\`\`bash
./install.sh
\`\`\`

### Manual Install
Copy the binaries from \`bin/\` to your PATH.

## Tools Overview

### Core Tools
- **zmin**: Main JSON minifier with multiple optimization modes
- **debugger**: Performance analysis and debugging tool
- **dev-server**: Development server with API endpoints
- **profiler**: Performance profiling and benchmarking

### Development Tools
- **config-manager**: Configuration file management
- **plugin-registry**: Plugin discovery and management
- **hot-reloading**: File watching and auto-reload

## Quick Start

1. Start the development server:
   \`\`\`bash
   ./bin/dev-server 8080
   \`\`\`

2. Run performance analysis:
   \`\`\`bash
   echo '{"test": "data"}' | ./bin/debugger --benchmark 50
   \`\`\`

3. Profile different modes:
   \`\`\`bash
   ./bin/profiler --input data.json --modes eco,sport,turbo
   \`\`\`

## Configuration

Copy \`examples/configs/zmin.config.json\` to your project and customize as needed.

## Examples

See \`examples/\` directory for usage examples and workflows.

## Documentation

- Tool-specific documentation: \`docs/tools/\`
- API documentation: \`docs/api/\`
- Examples and tutorials: \`examples/\`

## Support

- GitHub: https://github.com/user/zmin
- Issues: https://github.com/user/zmin/issues

---

Built for $PLATFORM-$ARCH • Version $VERSION
EOF

# Create checksums
log "Generating checksums..."
cd "$PACKAGE_PATH"
find bin -type f -exec sha256sum {} \; > CHECKSUMS.txt
success "Checksums generated"

# Create archive
log "Creating archive..."
cd "$PACKAGE_DIR"

case "$PLATFORM" in
    "windows")
        # Create ZIP for Windows
        if command -v zip >/dev/null 2>&1; then
            zip -r "$PACKAGE_NAME.zip" "$PACKAGE_NAME"
            success "Created $PACKAGE_NAME.zip"
        else
            warn "zip not available, skipping archive creation"
        fi
        ;;
    *)
        # Create tar.gz for Unix-like systems
        tar -czf "$PACKAGE_NAME.tar.gz" "$PACKAGE_NAME"
        success "Created $PACKAGE_NAME.tar.gz"
        ;;
esac

# Generate package info
cat > "$PACKAGE_DIR/package-info.json" << EOF
{
  "name": "zmin-dev-tools",
  "version": "$VERSION",
  "platform": "$PLATFORM",
  "architecture": "$ARCH",
  "package_name": "$PACKAGE_NAME",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tools": [
    $(printf '"%s"' "${DEV_TOOLS[0]}")
    $(printf ', "%s"' "${DEV_TOOLS[@]:1}")
  ],
  "checksums_file": "CHECKSUMS.txt",
  "archive": "$PACKAGE_NAME.tar.gz"
}
EOF

success "Package info generated"

# Summary
log "📦 Package Summary"
echo "===================="
echo "Package: $PACKAGE_NAME"
echo "Version: $VERSION"
echo "Platform: $PLATFORM-$ARCH"
echo "Location: $PACKAGE_PATH"
if [ -f "$PACKAGE_NAME.tar.gz" ]; then
    echo "Archive: $PACKAGE_NAME.tar.gz"
    echo "Size: $(du -h "$PACKAGE_NAME.tar.gz" | cut -f1)"
elif [ -f "$PACKAGE_NAME.zip" ]; then
    echo "Archive: $PACKAGE_NAME.zip"
    echo "Size: $(du -h "$PACKAGE_NAME.zip" | cut -f1)"
fi
echo ""

success "✅ Dev tools packaging completed successfully!"
echo ""
echo "To test the package:"
echo "  cd $PACKAGE_PATH && ./examples/dev-workflow.sh"
echo ""
echo "To install:"
echo "  cd $PACKAGE_PATH && ./install.sh"