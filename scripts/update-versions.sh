#!/usr/bin/env bash
# Update version references in documentation files

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_status "Updating version references in documentation..."

# Read versions from JSON file
VERSIONS_FILE="${GITHUB_WORKSPACE:-.}/.github/versions.json"
if [ ! -f "$VERSIONS_FILE" ]; then
    print_error "versions.json not found at $VERSIONS_FILE"
    exit 1
fi

# Load versions
load_versions

print_status "Zig version: $ZIG_VERSION"
print_status "Zmin version: $ZMIN_VERSION"

# Update README.md badge
if [ -f "README.md" ]; then
    sed -i "s/zig-[0-9.]\+-orange/zig-${ZIG_VERSION}-orange/g" README.md
    print_success "Updated README.md"
fi

# Update documentation files
for doc in docs/*.md; do
    if [ -f "$doc" ]; then
        # Update Zig version references
        sed -i "s/Zig [0-9.]\+ or later/Zig ${ZIG_VERSION} or later/g" "$doc"
        sed -i "s/Version [0-9.]\+ or later/Version ${ZIG_VERSION} or later/g" "$doc"
        sed -i "s/download\/[0-9.]\+\/zig/download\/${ZIG_VERSION}\/zig/g" "$doc"
        sed -i "s/zig-linux-x86_64-[0-9.]\+/zig-linux-x86_64-${ZIG_VERSION}/g" "$doc"
        print_success "Updated $(basename "$doc")"
    fi
done

print_success "Version references updated successfully!"