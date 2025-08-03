#!/bin/bash
# zmin-auto - Intelligent mode selection for zmin
# Automatically selects the optimal zmin mode based on file size and system resources

# Default thresholds (customizable)
SMALL_FILE_THRESHOLD=$((1 * 1024 * 1024))      # 1 MB
LARGE_FILE_THRESHOLD=$((100 * 1024 * 1024))    # 100 MB
MIN_MEMORY_FOR_SPORT=$((100 * 1024 * 1024))    # 100 MB
MIN_MEMORY_FOR_TURBO=$((500 * 1024 * 1024))    # 500 MB

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Parse arguments
INPUT_FILE="$1"
OUTPUT_FILE="$2"

if [ -z "$INPUT_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: zmin-auto <input.json> <output.json>"
    echo ""
    echo "Automatically selects the optimal zmin mode based on:"
    echo "  - File size"
    echo "  - Available memory"
    echo "  - GPU availability"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --verbose  Show detailed decision process"
    echo "  -d, --dry-run  Show what would be done without executing"
    exit 1
fi

# Check for flags
VERBOSE=false
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        -v|--verbose)
            VERBOSE=true
            ;;
        -d|--dry-run)
            DRY_RUN=true
            ;;
    esac
done

# Get file size
FILE_SIZE=$(stat -c%s "$INPUT_FILE" 2>/dev/null || stat -f%z "$INPUT_FILE")

# Get available memory (Linux/macOS compatible)
if command -v free >/dev/null 2>&1; then
    # Linux
    AVAILABLE_MEM=$(free -b | awk '/^Mem:/{print $7}')
else
    # macOS
    AVAILABLE_MEM=$(vm_stat | awk '/free/ {print $3}' | sed 's/\.//')
    AVAILABLE_MEM=$((AVAILABLE_MEM * 4096))  # Convert pages to bytes
fi

# Check CPU cores
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)

# Logging function
log() {
    if [ "$VERBOSE" = true ]; then
        echo -e "$1"
    fi
}

# Determine optimal mode
select_mode() {
    log "${BLUE}Decision Process:${NC}"
    log "  File size: $(human_readable $FILE_SIZE)"
    log "  Available memory: $(human_readable $AVAILABLE_MEM)"
    log "  CPU cores: $CPU_CORES"
    
    # Check GPU availability
    if zmin --gpu-info >/dev/null 2>&1 && [ $FILE_SIZE -gt $LARGE_FILE_THRESHOLD ]; then
        log "  ${GREEN}✓ GPU available and file is large${NC}"
        echo "gpu"
        return
    fi
    
    # Memory-constrained environment
    if [ $AVAILABLE_MEM -lt $MIN_MEMORY_FOR_SPORT ]; then
        log "  ${YELLOW}⚠ Limited memory available${NC}"
        echo "eco"
        return
    fi
    
    # Small files
    if [ $FILE_SIZE -lt $SMALL_FILE_THRESHOLD ]; then
        log "  ${BLUE}→ Small file detected${NC}"
        if [ $AVAILABLE_MEM -lt $MIN_MEMORY_FOR_TURBO ]; then
            echo "sport"
        else
            echo "sport"  # SPORT is optimal for small files
        fi
        return
    fi
    
    # Large files
    if [ $FILE_SIZE -gt $LARGE_FILE_THRESHOLD ]; then
        log "  ${PURPLE}→ Large file detected${NC}"
        if [ $AVAILABLE_MEM -gt $MIN_MEMORY_FOR_TURBO ] && [ $CPU_CORES -ge 4 ]; then
            echo "turbo"
        else
            echo "sport"
        fi
        return
    fi
    
    # Medium files - default to SPORT
    log "  ${BLUE}→ Medium file, using balanced mode${NC}"
    echo "sport"
}

# Convert bytes to human readable format
human_readable() {
    local bytes=$1
    if [ $bytes -gt $((1024 * 1024 * 1024)) ]; then
        echo "$(( bytes / 1024 / 1024 / 1024 )) GB"
    elif [ $bytes -gt $((1024 * 1024)) ]; then
        echo "$(( bytes / 1024 / 1024 )) MB"
    else
        echo "$(( bytes / 1024 )) KB"
    fi
}

# Estimate processing time
estimate_time() {
    local mode=$1
    local throughput_mbs=555  # Default SPORT
    
    case $mode in
        eco)
            throughput_mbs=312
            ;;
        sport)
            throughput_mbs=555
            ;;
        turbo)
            throughput_mbs=1100
            ;;
        gpu)
            throughput_mbs=2000
            ;;
    esac
    
    local file_size_mb=$(( FILE_SIZE / 1024 / 1024 ))
    if [ $file_size_mb -eq 0 ]; then
        file_size_mb=1
    fi
    
    local est_seconds=$(( file_size_mb * 1000 / throughput_mbs ))
    if [ $est_seconds -lt 1000 ]; then
        echo "${est_seconds}ms"
    else
        echo "$(( est_seconds / 1000 )).$(( est_seconds % 1000 / 100 ))s"
    fi
}

# Select mode
MODE=$(select_mode)

# Build command
if [ "$MODE" = "gpu" ]; then
    COMMAND="zmin --gpu auto \"$INPUT_FILE\" \"$OUTPUT_FILE\""
else
    COMMAND="zmin --mode $MODE \"$INPUT_FILE\" \"$OUTPUT_FILE\""
fi

# Show decision
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${BLUE}        zmin Auto Mode Selection       ${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "File: ${GREEN}$INPUT_FILE${NC}"
echo -e "Size: ${YELLOW}$(human_readable $FILE_SIZE)${NC}"
echo -e "Available Memory: ${YELLOW}$(human_readable $AVAILABLE_MEM)${NC}"
echo -e "CPU Cores: ${YELLOW}$CPU_CORES${NC}"
echo -e "Selected Mode: ${PURPLE}${MODE^^}${NC}"
echo -e "Estimated Time: ${GREEN}$(estimate_time $MODE)${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo ""
echo -e "Command: ${GREEN}$COMMAND${NC}"

# Execute or show dry run
if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "${YELLOW}[DRY RUN] Would execute:${NC} $COMMAND"
else
    echo ""
    eval "$COMMAND"
fi