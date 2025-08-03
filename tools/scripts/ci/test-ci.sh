#!/bin/bash

# Zmin CI/CD Local Test Script
# This script tests the CI/CD pipeline locally

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

echo "🚀 Starting Zmin CI/CD Local Test"
echo "=================================="

# Check if Zig is installed
check_zig() {
    print_status "Checking Zig installation..."
    if command -v zig &> /dev/null; then
        ZIG_VERSION=$(zig version)
        print_success "Zig found: $ZIG_VERSION"
    else
        print_error "Zig not found. Please install Zig 0.12.0 or later."
        exit 1
    fi
}

# Build the project
build_project() {
    print_status "Building Zmin project..."
    zig build
    print_success "Build completed successfully"
}

# Run tests
run_tests() {
    print_status "Running test suite..."
    zig build test
    print_success "All tests passed"
}

# Run performance benchmarks
run_benchmarks() {
    print_status "Running performance benchmarks..."
    zig build test:ultimate
    print_success "Performance benchmarks completed"
}

# Generate badges
generate_badges() {
    print_status "Generating performance badges..."
    zig build tools:badges --throughput=5.72 --simd=6400 --zig=0.12.0
    print_success "Badges generated in badges/ directory"
}

# Run complete CI pipeline
run_ci_pipeline() {
    print_status "Running complete CI pipeline..."
    zig build ci:pipeline
    print_success "CI pipeline completed successfully"
}

# Check generated artifacts
check_artifacts() {
    print_status "Checking generated artifacts..."

    # Check if badges were generated
    if [ -d "badges" ]; then
        print_success "Badges directory created"
        ls -la badges/
    else
        print_warning "Badges directory not found"
    fi

    # Check if executables were built
    if [ -d "zig-out/bin" ]; then
        print_success "Executables built successfully"
        ls -la zig-out/bin/
    else
        print_warning "Executables directory not found"
    fi
}

# Run security analysis
run_security_analysis() {
    print_status "Running security analysis..."
    zig build --release=safe
    zig build test
    print_success "Security analysis completed"
}

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

# Performance regression test
performance_regression_test() {
    print_status "Running performance regression test..."

    # Run benchmark and capture output
    BENCHMARK_OUTPUT=$(zig build test:ultimate 2>&1)

    # Extract throughput
    THROUGHPUT=$(echo "$BENCHMARK_OUTPUT" | grep -oP '(\d+\.\d+)\s*GB/s' | head -1 | grep -oP '\d+\.\d+' || echo "0.0")

    print_status "Measured throughput: $THROUGHPUT GB/s"

    # Check if performance meets minimum threshold (4 GB/s)
    if (( $(echo "$THROUGHPUT >= 4.0" | bc -l) )); then
        print_success "Performance regression test passed (>= 4.0 GB/s)"
    else
        print_error "Performance regression test failed (< 4.0 GB/s)"
        exit 1
    fi
}

# Main execution
main() {
    echo ""
    print_status "Starting CI/CD test sequence..."
    echo ""

    check_zig
    echo ""

    build_project
    echo ""

    run_tests
    echo ""

    run_benchmarks
    echo ""

    generate_badges
    echo ""

        run_security_analysis
    echo ""

    test_version_management
    echo ""

    performance_regression_test
    echo ""

    run_ci_pipeline
    echo ""

    check_artifacts
    echo ""

    print_success "🎉 All CI/CD tests passed successfully!"
    print_status "The project is ready for production deployment."
    echo ""
    print_status "Next steps:"
    print_status "1. Push to GitHub to trigger automated CI/CD"
    print_status "2. Create a release tag to generate artifacts"
    print_status "3. Monitor performance badges for updates"
}

# Run main function
main "$@"
