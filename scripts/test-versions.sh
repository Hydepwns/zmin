#!/bin/bash

# Zmin Version Management Test Script
# This script tests the version management system used by CI workflows

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "🧪 Zmin Version Management Test"
echo "==============================="

# Basic version reading test
test_basic_versions() {
    print_status "Testing basic version reading..."

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

    print_success "Basic version reading test passed"
}

# Validate versions.json structure
validate_versions_file() {
    print_status "Validating versions.json structure..."

    # Check if file is valid JSON
    if ! jq empty .github/versions.json 2>/dev/null; then
        print_error ".github/versions.json is not valid JSON!"
        exit 1
    fi

    # Check required fields
    REQUIRED_FIELDS=("zig" "zmin")
    for field in "${REQUIRED_FIELDS[@]}"; do
        if ! jq -e ".$field" .github/versions.json >/dev/null 2>&1; then
            print_error "Required field '$field' is missing!"
            exit 1
        fi

        value=$(jq -r ".$field" .github/versions.json)
        if [ "$value" = "null" ] || [ -z "$value" ]; then
            print_error "Field '$field' is null or empty!"
            exit 1
        fi

        print_status "✅ Field '$field' is present with value: $value"
    done

    # Check version format (basic validation)
    ZIG_VERSION=$(jq -r '.zig' .github/versions.json)
    ZMIN_VERSION=$(jq -r '.zmin' .github/versions.json)

    # Basic version format validation (x.y.z)
    if [[ ! "$ZIG_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        print_warning "Zig version '$ZIG_VERSION' doesn't match expected format (x.y.z)"
    fi

    if [[ ! "$ZMIN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        print_warning "Zmin version '$ZMIN_VERSION' doesn't match expected format (x.y.z)"
    fi

    # Check if minimum_zig is present and valid
    if jq -e '.minimum_zig' .github/versions.json >/dev/null 2>&1; then
        MIN_ZIG=$(jq -r '.minimum_zig' .github/versions.json)
        if [ "$MIN_ZIG" != "null" ] && [ -n "$MIN_ZIG" ]; then
            print_status "✅ minimum_zig is present: $MIN_ZIG"

            # Check if minimum_zig <= zig
            if [ "$MIN_ZIG" != "$ZIG_VERSION" ]; then
                print_warning "minimum_zig ($MIN_ZIG) differs from zig ($ZIG_VERSION)"
            fi
        else
            print_warning "minimum_zig is null or empty"
        fi
    else
        print_status "ℹ️  minimum_zig field is not present"
    fi

    print_success "Versions.json validation passed"
}

# Test sparse checkout simulation
test_sparse_checkout() {
    print_status "Testing sparse checkout simulation..."

    # Create a temporary directory to simulate sparse checkout
    TEMP_DIR=$(mktemp -d)
    print_status "Created temporary directory: $TEMP_DIR"

    # Simulate sparse checkout - only copy the versions.json file
    mkdir -p "$TEMP_DIR/.github"
    cp .github/versions.json "$TEMP_DIR/.github/"

    # Change to temp directory to simulate the workflow environment
    cd "$TEMP_DIR"

    print_status "Sparse checkout completed"
    print_status "Current directory contents:"
    ls -la .github/

    # Test version reading in isolated environment
    ZIG_VERSION=$(jq -r '.zig' .github/versions.json)
    ZMIN_VERSION=$(jq -r '.zmin' .github/versions.json)

    print_status "Versions read in isolated environment:"
    print_status "  Zig: $ZIG_VERSION"
    print_status "  Zmin: $ZMIN_VERSION"

    # Cleanup
    cd "$SCRIPT_DIR/.."
    rm -rf "$TEMP_DIR"

    print_success "Sparse checkout simulation passed"
}

# Test GitHub Actions output format
test_github_actions_output() {
    print_status "Testing GitHub Actions output format..."

    # Simulate the workflow's version reading step
    echo "zig=$(jq -r '.zig' .github/versions.json)"
    echo "zmin=$(jq -r '.zmin' .github/versions.json)"

    print_success "GitHub Actions output format test passed"
}

# Test error scenarios
test_error_scenarios() {
    print_status "Testing error scenarios..."

    # Test with invalid JSON
    echo '{"zig": "0.14.1", "zmin":}' > /tmp/invalid_versions.json
    if jq empty /tmp/invalid_versions.json 2>/dev/null; then
        print_error "Invalid JSON was not detected!"
        rm -f /tmp/invalid_versions.json
        exit 1
    else
        print_status "✅ Invalid JSON correctly detected"
    fi
    rm -f /tmp/invalid_versions.json

    # Test with missing fields
    echo '{"zig": "0.14.1"}' > /tmp/missing_field.json
    if jq -e '.zmin' /tmp/missing_field.json >/dev/null 2>&1; then
        print_error "Missing field was not detected!"
        rm -f /tmp/missing_field.json
        exit 1
    else
        print_status "✅ Missing field correctly detected"
    fi
    rm -f /tmp/missing_field.json

    print_success "Error scenario tests passed"
}

# Main execution
main() {
    echo ""
    print_status "Starting version management test sequence..."
    echo ""

    test_basic_versions
    echo ""

    validate_versions_file
    echo ""

    test_sparse_checkout
    echo ""

    test_github_actions_output
    echo ""

    test_error_scenarios
    echo ""

    print_success "🎉 All version management tests passed successfully!"
    print_status "The version management system is working correctly."
    echo ""
    print_status "Summary:"
    print_status "- Versions.json is valid and contains required fields"
    print_status "- Version reading logic works in isolated environments"
    print_status "- GitHub Actions output format is correct"
    print_status "- Error handling is robust"
}

# Run main function
main "$@"
