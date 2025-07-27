#!/bin/bash

# Zmin Project Organization Script
# Ensures proper directory structure and organization

set -e

echo "📁 Organizing zmin project structure..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

print_status "Project root: $PROJECT_ROOT"

# Create essential directories if they don't exist
print_status "Ensuring essential directories exist..."

DIRS=(
    "src"
    "tests"
    "examples"
    "benchmarks"
    "tools"
    "scripts"
    "docs"
    "bindings"
    "homebrew"
    "archive"
    ".github"
)

for dir in "${DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        print_success "Created directory: $dir"
    else
        print_status "Directory exists: $dir"
    fi
done

# Create subdirectories for better organization
print_status "Creating subdirectories for better organization..."

# Create src subdirectories
mkdir -p src/{core,utils,parsers,formatters,optimizers}
print_success "Created src subdirectories"

# Create tests subdirectories
mkdir -p tests/{unit,integration,performance,regression}
print_success "Created tests subdirectories"

# Create examples subdirectories
mkdir -p examples/{basic,advanced,benchmarks}
print_success "Created examples subdirectories"

# Create docs subdirectories
mkdir -p docs/{api,guides,examples,performance}
print_success "Created docs subdirectories"

# Create tools subdirectories
mkdir -p tools/{build,test,benchmark,development}
print_success "Created tools subdirectories"

# Create scripts subdirectories
mkdir -p scripts/{build,test,deploy,maintenance}
print_success "Created scripts subdirectories"

# Move existing scripts to appropriate subdirectories
print_status "Organizing existing scripts..."

# Move build-related scripts
if [ -f "scripts/build_simple.zig" ]; then
    mv scripts/build_simple.zig scripts/build/ 2>/dev/null || true
fi

if [ -f "scripts/generate-api-docs.zig" ]; then
    mv scripts/generate-api-docs.zig scripts/build/ 2>/dev/null || true
fi

# Move test-related scripts
if [ -f "scripts/test-ci.sh" ]; then
    mv scripts/test-ci.sh scripts/test/ 2>/dev/null || true
fi

if [ -f "scripts/benchmark-single.sh" ]; then
    mv scripts/benchmark-single.sh scripts/test/ 2>/dev/null || true
fi

# Move maintenance scripts
if [ -f "scripts/cleanup.sh" ]; then
    mv scripts/cleanup.sh scripts/maintenance/ 2>/dev/null || true
fi

if [ -f "scripts/update-versions.sh" ]; then
    mv scripts/update-versions.sh scripts/maintenance/ 2>/dev/null || true
fi

if [ -f "scripts/update-performance-data.sh" ]; then
    mv scripts/update-performance-data.sh scripts/maintenance/ 2>/dev/null || true
fi

# Create README files for each directory
print_status "Creating README files for directories..."

create_readme() {
    local dir="$1"
    local title="$2"
    local content="$3"

    if [ ! -f "$dir/README.md" ]; then
        cat > "$dir/README.md" << EOF
# $title

$content

## Contents

This directory contains:

$(ls -1 "$dir" 2>/dev/null | grep -v README.md | sed 's/^/- /' || echo "- (empty)")

EOF
        print_success "Created README for $dir"
    fi
}

create_readme "src" "Source Code" "Core source code for the zmin project."
create_readme "tests" "Tests" "Test suites for the zmin project."
create_readme "examples" "Examples" "Example code demonstrating zmin usage."
create_readme "benchmarks" "Benchmarks" "Performance benchmarks and tests."
create_readme "tools" "Tools" "Development and build tools."
create_readme "scripts" "Scripts" "Utility scripts for development and maintenance."
create_readme "docs" "Documentation" "Project documentation and guides."
create_readme "bindings" "Language Bindings" "Language bindings and interfaces."
create_readme "homebrew" "Homebrew" "Homebrew formula and packaging."
create_readme "archive" "Archive" "Archived files and old versions."

# Create .gitkeep files for empty directories to ensure they're tracked
print_status "Ensuring empty directories are tracked by git..."

find . -type d -empty -not -path "./.git*" -not -path "./.zig-cache*" -exec touch {}/.gitkeep \;

# Show final structure
print_status "Project structure summary:"
echo ""
echo "📁 Root directories:"
for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        count=$(find "$dir" -type f -not -name ".gitkeep" | wc -l)
        echo "  $dir/ ($count files)"
    fi
done

echo ""
echo "📁 Source organization:"
if [ -d "src" ]; then
    for subdir in src/*/; do
        if [ -d "$subdir" ]; then
            count=$(find "$subdir" -type f | wc -l)
            echo "  $subdir ($count files)"
        fi
    done
fi

print_success "🎉 Project organization completed!"
print_status "You can now run 'make build' to build the project"
