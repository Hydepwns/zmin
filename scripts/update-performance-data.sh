#!/bin/bash

# Performance Data Update Script
# This script helps maintain consistency of performance data across documentation

set -e

# Canonical performance data (single source of truth)
ECO_SPEED="580 MB/s"
ECO_MEMORY="64KB"
SPORT_SPEED="850 MB/s"
SPORT_MEMORY="O(√n)"
TURBO_SPEED="3.5+ GB/s"
TURBO_MEMORY="O(n)"

echo "📊 Zmin Performance Data Consistency Check"
echo "=========================================="
echo

# Check for inconsistencies in key files
echo "Checking for performance data inconsistencies..."

# Files to check
FILES=(
    "README.md"
    "PERFORMANCE_MODES.md"
    "QUICK_REFERENCE.md"
    "docs/performance-data.md"
    ".github/workflows/ci.yml"
    ".github/workflows/release.yml"
    ".github/ISSUE_TEMPLATE/performance_issue.yml"
)

for file in "${FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo "✅ $file exists"
        
        # Check for ECO speed inconsistencies
        if grep -q "579 MB/s\|581 MB/s\|570 MB/s\|590 MB/s" "$file"; then
            echo "⚠️  $file: ECO speed inconsistency detected"
        fi
        
        # Check for TURBO speed inconsistencies  
        if grep -q "2\.5\+ GB/s\|3\.0\+ GB/s\|4\.0\+ GB/s" "$file"; then
            echo "⚠️  $file: TURBO speed inconsistency detected"
        fi
    else
        echo "❌ $file: File not found"
    fi
done

echo
echo "📋 Canonical Performance Data:"
echo "=============================="
echo "ECO:     $ECO_SPEED, $ECO_MEMORY"
echo "SPORT:   $SPORT_SPEED, $SPORT_MEMORY" 
echo "TURBO:   $TURBO_SPEED, $TURBO_MEMORY"
echo
echo "💡 To update performance data:"
echo "1. Edit docs/performance-data.md (single source of truth)"
echo "2. Run this script to check for inconsistencies"
echo "3. Update other files as needed" 