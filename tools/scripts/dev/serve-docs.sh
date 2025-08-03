#!/bin/bash

# Serve Hugo documentation site locally
set -e

echo "Starting Hugo development server..."

# Check if site is built
if [ ! -d "public" ]; then
    echo "Site not built yet. Building first..."
    nix-shell -p hugo go --run "hugo --minify"
fi

# Start Hugo server
echo "Starting server at http://localhost:1313"
echo "Press Ctrl+C to stop"
nix-shell -p hugo go --run "hugo server --bind 0.0.0.0 --port 1313 --baseURL http://localhost:1313/"
