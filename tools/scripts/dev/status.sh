#!/bin/bash

# Zmin Project Status Script
# Shows current project status and identifies cleanup opportunities

set -e

echo "📊 Zmin Project Status Report"
echo "=============================="

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo ""
print_info "Project root: $PROJECT_ROOT"

# Check project size
if command -v du &> /dev/null; then
    TOTAL_SIZE=$(du -sh . 2>/dev/null | cut -f1 || echo "unknown")
    print_info "Total project size: $TOTAL_SIZE"
fi

echo ""
echo "📁 Directory Structure:"
echo "----------------------"

# Count files in each directory
DIRS=("src" "tests" "examples" "benchmarks" "tools" "scripts" "docs" "bindings" "homebrew" "archive")

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        count=$(find "$dir" -type f | wc -l)
        size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "0")
        echo "  $dir/ ($count files, $size)"
    else
        echo "  $dir/ (missing)"
    fi
done

echo ""
echo "🧹 Cleanup Status:"
echo "-----------------"

# Check for build artifacts
BUILD_ARTIFACTS=0
if [ -d ".zig-cache" ]; then
    cache_size=$(du -sh .zig-cache 2>/dev/null | cut -f1 || echo "unknown")
    print_warning "Zig cache found: .zig-cache/ ($cache_size)"
    BUILD_ARTIFACTS=$((BUILD_ARTIFACTS + 1))
fi

if [ -d "zig-out" ]; then
    out_size=$(du -sh zig-out 2>/dev/null | cut -f1 || echo "unknown")
    print_warning "Zig output found: zig-out/ ($out_size)"
    BUILD_ARTIFACTS=$((BUILD_ARTIFACTS + 1))
fi

# Check for object files
OBJECT_FILES=$(find . -maxdepth 1 -name "*.o" | wc -l)
if [ "$OBJECT_FILES" -gt 0 ]; then
    print_warning "Object files in root: $OBJECT_FILES files"
    BUILD_ARTIFACTS=$((BUILD_ARTIFACTS + OBJECT_FILES))
fi

# Check for executables
EXECUTABLES=$(find . -maxdepth 1 -type f -executable | grep -v "\.sh$" | grep -v "\.py$" | wc -l)
if [ "$EXECUTABLES" -gt 0 ]; then
    print_warning "Executables in root: $EXECUTABLES files"
    BUILD_ARTIFACTS=$((BUILD_ARTIFACTS + EXECUTABLES))
fi

# Check for libraries
LIBRARIES=$(find . -maxdepth 1 -name "*.a" -o -name "*.so" -o -name "*.dylib" -o -name "*.dll" | wc -l)
if [ "$LIBRARIES" -gt 0 ]; then
    print_warning "Libraries in root: $LIBRARIES files"
    BUILD_ARTIFACTS=$((BUILD_ARTIFACTS + LIBRARIES))
fi

# Check for temporary files
TEMP_FILES=$(find . -maxdepth 1 -name "*.tmp" -o -name "*.temp" -o -name "*.log" | wc -l)
if [ "$TEMP_FILES" -gt 0 ]; then
    print_warning "Temporary files in root: $TEMP_FILES files"
    BUILD_ARTIFACTS=$((BUILD_ARTIFACTS + TEMP_FILES))
fi

# Check for output files
OUTPUT_FILES=$(find . -maxdepth 1 -name "*_out.json" -o -name "*_output.json" -o -name "*.output" -o -name "*.minified" | wc -l)
if [ "$OUTPUT_FILES" -gt 0 ]; then
    print_warning "Output files in root: $OUTPUT_FILES files"
    BUILD_ARTIFACTS=$((BUILD_ARTIFACTS + OUTPUT_FILES))
fi

if [ "$BUILD_ARTIFACTS" -eq 0 ]; then
    print_success "No build artifacts found - project is clean!"
else
    print_warning "Found $BUILD_ARTIFACTS build artifacts that can be cleaned"
fi

echo ""
echo "🔧 Development Tools:"
echo "-------------------"

# Check for required tools
if command -v zig &> /dev/null; then
    ZIG_VERSION=$(zig version 2>/dev/null || echo "unknown")
    print_success "Zig: $ZIG_VERSION"
else
    print_error "Zig: not found"
fi

if command -v make &> /dev/null; then
    print_success "Make: available"
else
    print_error "Make: not found"
fi

if command -v git &> /dev/null; then
    print_success "Git: available"
else
    print_error "Git: not found"
fi

echo ""
echo "📋 Recommendations:"
echo "------------------"

if [ "$BUILD_ARTIFACTS" -gt 0 ]; then
    print_info "Run 'make cleanup' to remove build artifacts"
fi

if [ ! -d "src" ] || [ ! -d "tests" ] || [ ! -d "examples" ]; then
    print_info "Run 'make organize' to set up proper directory structure"
fi

print_info "Run 'make help' to see all available commands"

echo ""
print_success "Status report completed!"