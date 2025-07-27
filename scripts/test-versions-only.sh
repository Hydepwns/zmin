#!/bin/bash

# Minimal version testing script
# Tests only the version management functionality without requiring a full build

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "🧪 Testing Version Management Only"
echo "=================================="

# Test version management
test_version_management() {
    print_status "Testing version management..."

    # Check if versions.json exists
    if [ ! -f ".github/versions.json" ]; then
        print_error ".github/versions.json not found!"
        exit 1
    fi

    # Read versions using the same logic as the workflow
    ZIG_VERSION=$(jq -r '.zig' .github/versions.json)
    ZMIN_VERSION=$(jq -r '.zmin' .github/versions.json)

    print_status "Extracted versions:"
    print_status "  Zig version: $ZIG_VERSION"
    print_status "  Zmin version: $ZMIN_VERSION"

    # Validate versions are not empty
    if [ -z "$ZIG_VERSION" ] || [ "$ZIG_VERSION" = "null" ]; then
        print_error "Zig version is empty or null"
        exit 1
    fi

    if [ -z "$ZMIN_VERSION" ] || [ "$ZMIN_VERSION" = "null" ]; then
        print_error "Zmin version is empty or null"
        exit 1
    fi

    print_success "Version management test passed"
}

# Main execution
main() {
    echo ""
    print_status "Starting version management test..."
    echo ""

    test_version_management
    echo ""

    print_success "🎉 Version management test completed successfully!"
    print_status "The read-versions workflow would work correctly."
}

# Run main function
main "$@"
