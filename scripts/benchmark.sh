#!/bin/bash

# zmin Performance Benchmarking Script
# Tests different modes and configurations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BENCHMARK_DIR="benchmarks"
RESULTS_DIR="benchmark-results"
INPUT_FILES=(
    "small.json:1KB"
    "medium.json:1MB"
    "large.json:10MB"
    "huge.json:100MB"
)

# Create results directory
mkdir -p "$RESULTS_DIR"

echo -e "${BLUE}🚀 zmin Performance Benchmarking${NC}"
echo "=================================="

# Build the project
echo -e "${YELLOW}Building zmin...${NC}"
zig build --release=fast

# Function to run benchmark
run_benchmark() {
    local mode=$1
    local input_file=$2
    local output_file="$RESULTS_DIR/${mode}_${input_file}.json"

    echo -e "${GREEN}Testing ${mode} mode with ${input_file}...${NC}"

    # Time the operation
    start_time=$(date +%s.%N)
    ./zig-out/bin/zmin --mode "$mode" "$BENCHMARK_DIR/$input_file" "$output_file"
    end_time=$(date +%s.%N)

    # Calculate duration and throughput
    duration=$(echo "$end_time - $start_time" | bc -l)
    file_size=$(stat -c%s "$BENCHMARK_DIR/$input_file")
    throughput=$(echo "scale=2; $file_size / $duration / 1024 / 1024" | bc -l)

    echo "  Duration: ${duration}s"
    echo "  Throughput: ${throughput} MB/s"

    # Save results
    echo "{\"mode\":\"$mode\",\"file\":\"$input_file\",\"duration\":$duration,\"throughput\":$throughput}" >> "$RESULTS_DIR/results.json"
}

# Generate test files if they don't exist
echo -e "${YELLOW}Generating test files...${NC}"
mkdir -p "$BENCHMARK_DIR"

# Small file (1KB)
if [ ! -f "$BENCHMARK_DIR/small.json" ]; then
    echo '{"data":' > "$BENCHMARK_DIR/small.json"
    for i in {1..50}; do
        echo "{\"id\":$i,\"name\":\"item$i\",\"value\":$(($RANDOM % 1000))}" >> "$BENCHMARK_DIR/small.json"
        if [ $i -lt 50 ]; then echo "," >> "$BENCHMARK_DIR/small.json"; fi
    done
    echo "}" >> "$BENCHMARK_DIR/small.json"
fi

# Medium file (1MB)
if [ ! -f "$BENCHMARK_DIR/medium.json" ]; then
    echo '{"data":[' > "$BENCHMARK_DIR/medium.json"
    for i in {1..5000}; do
        echo "{\"id\":$i,\"name\":\"item$i\",\"value\":$(($RANDOM % 1000)),\"nested\":{\"a\":$i,\"b\":\"string$i\"}}" >> "$BENCHMARK_DIR/medium.json"
        if [ $i -lt 5000 ]; then echo "," >> "$BENCHMARK_DIR/medium.json"; fi
    done
    echo "]}" >> "$BENCHMARK_DIR/medium.json"
fi

# Large file (10MB) - only create if requested
if [ "$1" = "--large" ] && [ ! -f "$BENCHMARK_DIR/large.json" ]; then
    echo -e "${YELLOW}Generating large test file (this may take a while)...${NC}"
    echo '{"data":[' > "$BENCHMARK_DIR/large.json"
    for i in {1..50000}; do
        echo "{\"id\":$i,\"name\":\"item$i\",\"value\":$(($RANDOM % 1000)),\"nested\":{\"a\":$i,\"b\":\"string$i\",\"c\":[1,2,3,4,5]}}" >> "$BENCHMARK_DIR/large.json"
        if [ $i -lt 50000 ]; then echo "," >> "$BENCHMARK_DIR/large.json"; fi
    done
    echo "]}" >> "$BENCHMARK_DIR/large.json"
fi

# Initialize results file
echo "[]" > "$RESULTS_DIR/results.json"

# Run benchmarks for each mode
modes=("eco" "sport" "turbo")
files=("small.json" "medium.json")

if [ "$1" = "--large" ]; then
    files+=("large.json")
fi

for mode in "${modes[@]}"; do
    for file in "${files[@]}"; do
        if [ -f "$BENCHMARK_DIR/$file" ]; then
            run_benchmark "$mode" "$file"
        fi
    done
done

# Generate summary report
echo -e "${BLUE}📊 Benchmark Summary${NC}"
echo "=================="

# Parse results and create summary
echo "| Mode | File | Duration (s) | Throughput (MB/s) |" > "$RESULTS_DIR/summary.md"
echo "|------|------|-------------|-------------------|" >> "$RESULTS_DIR/summary.md"

while IFS= read -r line; do
    if [ "$line" != "[]" ]; then
        mode=$(echo "$line" | jq -r '.mode')
        file=$(echo "$line" | jq -r '.file')
        duration=$(echo "$line" | jq -r '.duration')
        throughput=$(echo "$line" | jq -r '.throughput')
        printf "| %s | %s | %.3f | %.2f |\n" "$mode" "$file" "$duration" "$throughput" >> "$RESULTS_DIR/summary.md"
    fi
done < "$RESULTS_DIR/results.json"

cat "$RESULTS_DIR/summary.md"

echo -e "${GREEN}✅ Benchmarking complete! Results saved to $RESULTS_DIR/${NC}"
