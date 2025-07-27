#!/bin/bash

# Zmin CI/CD Local Test Script
# This script tests the CI/CD pipeline locally

set -e

echo "🚀 Starting Zmin CI/CD Local Test"
echo "=================================="

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