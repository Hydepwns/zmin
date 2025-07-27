#!/usr/bin/env bash
# Common functions and constants for zmin scripts

# Status indicators
readonly SUCCESS_ICON="✅"
readonly FAILURE_ICON="❌"
readonly NEUTRAL_ICON="➖"
readonly WARNING_ICON="⚠️"
readonly INFO_ICON="ℹ️"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Common paths
readonly BENCHMARKS_DIR="benchmarks/datasets"
readonly SCRIPTS_DIR="scripts"
readonly ZIG_OUT_DIR="zig-out/bin"

# Load version information
load_versions() {
    local versions_file="${GITHUB_WORKSPACE:-.}/.github/versions.json"
    if [ -f "$versions_file" ]; then
        export ZIG_VERSION=$(jq -r '.zig' "$versions_file")
        export ZMIN_VERSION=$(jq -r '.zmin' "$versions_file")
        export MIN_ZIG_VERSION=$(jq -r '.minimum_zig' "$versions_file")
    else
        # Fallback values
        export ZIG_VERSION="0.14.1"
        export ZMIN_VERSION="1.0.0"
        export MIN_ZIG_VERSION="0.14.1"
    fi
}

# Status printing functions
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} ${SUCCESS_ICON} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} ${FAILURE_ICON} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} ${WARNING_ICON} $1"
}

print_neutral() {
    echo -e "${BLUE}[INFO]${NC} ${NEUTRAL_ICON} $1"
}

# Setup benchmark datasets
setup_benchmark_datasets() {
    if [ ! -d "$BENCHMARKS_DIR" ]; then
        print_status "Creating benchmark datasets..."
        mkdir -p "$BENCHMARKS_DIR"
        if [ -f "$SCRIPTS_DIR/generate_test_data.py" ]; then
            python3 "$SCRIPTS_DIR/generate_test_data.py"
            print_success "Benchmark datasets created"
        else
            print_error "generate_test_data.py not found"
            return 1
        fi
    else
        print_status "Benchmark datasets already exist"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install system packages if not present
ensure_package() {
    local package=$1
    if ! command_exists "$package"; then
        print_status "Installing $package..."
        sudo apt-get update -qq
        sudo apt-get install -y "$package"
    fi
}

# Calculate percentage change
calculate_percentage_change() {
    local baseline=$1
    local current=$2
    echo "scale=2; (($current - $baseline) / $baseline) * 100" | bc
}

# Format performance result
format_performance_result() {
    local dataset=$1
    local change=$2

    # Use higher threshold for CI environments to account for runner variability
    local regression_threshold=10  # Increased from 5% to 10%
    local improvement_threshold=-5  # Keep improvement threshold at -5%

    if (( $(echo "$change < $improvement_threshold" | bc -l) )); then
        echo "${SUCCESS_ICON} **$dataset**: ${change}% (improvement)"
    elif (( $(echo "$change > $regression_threshold" | bc -l) )); then
        echo "${FAILURE_ICON} **$dataset**: +${change}% (regression)"
    else
        echo "${NEUTRAL_ICON} **$dataset**: ${change}% (no significant change)"
    fi
}

# Load versions on script source
load_versions
