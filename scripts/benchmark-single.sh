#!/usr/bin/env bash
# Benchmark a single minification operation
# Usage: ./benchmark-single.sh <binary> <input_file>

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

BINARY=$1
INPUT=$2
OUTPUT="/tmp/zmin-benchmark-output.json"

# Number of iterations
ITERATIONS=5

# Check if binary exists
if [ ! -x "$BINARY" ]; then
    echo "Error: Binary $BINARY not found or not executable" >&2
    exit 1
fi

# Check if input file exists
if [ ! -f "$INPUT" ]; then
    echo "Error: Input file $INPUT not found" >&2
    exit 1
fi

# Run warmup
for i in {1..2}; do
    if ! $BINARY $INPUT -o $OUTPUT >/dev/null 2>&1; then
        echo "Error: Failed to run $BINARY" >&2
        exit 1
    fi
done

# Run timed iterations
total_time=0
for i in $(seq 1 $ITERATIONS); do
    start=$(date +%s%N)
    if ! $BINARY $INPUT -o $OUTPUT >/dev/null 2>&1; then
        echo "Error: Failed to run $BINARY" >&2
        exit 1
    fi
    end=$(date +%s%N)
    
    # Calculate time in milliseconds
    time_ms=$(( (end - start) / 1000000 ))
    total_time=$((total_time + time_ms))
done

# Calculate average
avg_time=$((total_time / ITERATIONS))

# Output average time in milliseconds
echo $avg_time