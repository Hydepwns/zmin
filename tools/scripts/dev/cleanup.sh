#!/bin/bash

# Zmin Project Cleanup Script
# Removes all build artifacts, temporary files, and generated content

set -e

echo "🧹 Starting comprehensive cleanup of zmin project..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
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

print_status "Project root: $PROJECT_ROOT"

# 1. Clean Zig build artifacts
print_status "Cleaning Zig build artifacts..."
if command -v zig &> /dev/null; then
    zig build clean 2>/dev/null || print_warning "zig build clean failed (this is normal if no build exists)"
else
    print_warning "Zig not found, skipping zig build clean"
fi

# 2. Remove Zig cache and output directories
print_status "Removing Zig cache and output directories..."
rm -rf .zig-cache/ 2>/dev/null || true
rm -rf zig-out/ 2>/dev/null || true

# 3. Remove build artifacts
print_status "Removing build artifacts..."
rm -f *.o *.a *.so *.dylib *.dll *.exe 2>/dev/null || true
rm -f numa_allocator test_* lib*_test.a 2>/dev/null || true
rm -f generate-api-docs generate-api-docs.o 2>/dev/null || true

# 4. Remove temporary and output files
print_status "Removing temporary and output files..."
rm -f *.tmp *.temp *.log 2>/dev/null || true
rm -f *_out.json *_output.json 2>/dev/null || true
rm -f *.output *.minified 2>/dev/null || true

# 5. Remove build directories
print_status "Removing build directories..."
rm -rf build/ dist/ target/ 2>/dev/null || true

# 6. Clean documentation artifacts
print_status "Cleaning documentation artifacts..."
rm -f docs/api-reference-generated.json 2>/dev/null || true

# 7. Clean test artifacts
print_status "Cleaning test artifacts..."
find . -name "test_*.json" -delete 2>/dev/null || true
find . -name "test_*.minified" -delete 2>/dev/null || true
find . -name "test_*.output" -delete 2>/dev/null || true

# 8. Clean examples artifacts
print_status "Cleaning examples artifacts..."
find examples/ -name "*.o" -delete 2>/dev/null || true
find examples/ -name "*.exe" -delete 2>/dev/null || true
find examples/ -name "*.minified" -delete 2>/dev/null || true

# 9. Clean tools artifacts
print_status "Cleaning tools artifacts..."
find tools/ -name "*.o" -delete 2>/dev/null || true
find tools/ -name "*.exe" -delete 2>/dev/null || true

# 10. Clean benchmarks artifacts
print_status "Cleaning benchmarks artifacts..."
find benchmarks/ -name "*.o" -delete 2>/dev/null || true
find benchmarks/ -name "*.exe" -delete 2>/dev/null || true
find benchmarks/ -name "*.minified" -delete 2>/dev/null || true

# 11. Clean Docker artifacts (optional)
if [ "$1" = "--docker" ]; then
    print_status "Cleaning Docker artifacts..."
    docker system prune -f 2>/dev/null || print_warning "Docker cleanup failed"
fi

# 12. Show what was cleaned
print_status "Cleanup summary:"
echo "  ✅ Zig build artifacts"
echo "  ✅ Object files (*.o)"
echo "  ✅ Libraries (*.a, *.so, *.dylib, *.dll)"
echo "  ✅ Executables (*.exe)"
echo "  ✅ Temporary files (*.tmp, *.temp, *.log)"
echo "  ✅ Output files (*_out.json, *_output.json)"
echo "  ✅ Build directories (build/, dist/, target/)"
echo "  ✅ Documentation artifacts"
echo "  ✅ Test artifacts"
echo "  ✅ Examples artifacts"
echo "  ✅ Tools artifacts"
echo "  ✅ Benchmarks artifacts"

# 13. Show disk space saved
print_status "Checking disk usage..."
if command -v du &> /dev/null; then
    CURRENT_SIZE=$(du -sh . 2>/dev/null | cut -f1 || echo "unknown")
    print_success "Current project size: $CURRENT_SIZE"
fi

print_success "🎉 Cleanup completed successfully!"
print_status "You can now run 'make build' to rebuild the project"

# Optional: Show what files remain
if [ "$1" = "--verbose" ]; then
    print_status "Remaining files in project root:"
    ls -la | grep -E '^-' | awk '{print $9}' | grep -v '^\.$' | grep -v '^\.\.$' || true
fi
