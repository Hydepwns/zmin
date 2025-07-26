#!/bin/bash
# Benchmark a single minification operation
# Usage: ./benchmark-single.sh <binary> <mode> <input_file>

set -euo pipefail

BINARY=$1
MODE=$2
INPUT=$3
OUTPUT="/tmp/zmin-benchmark-output.json"

# Number of iterations
ITERATIONS=5

# Run warmup
for i in {1..2}; do
    $BINARY --mode $MODE $INPUT $OUTPUT >/dev/null 2>&1
done

# Run timed iterations
total_time=0
for i in $(seq 1 $ITERATIONS); do
    start=$(date +%s%N)
    $BINARY --mode $MODE $INPUT $OUTPUT >/dev/null 2>&1
    end=$(date +%s%N)
    
    # Calculate time in milliseconds
    time_ms=$(( (end - start) / 1000000 ))
    total_time=$((total_time + time_ms))
done

# Calculate average
avg_time=$((total_time / ITERATIONS))

# Output average time in milliseconds
echo $avg_time