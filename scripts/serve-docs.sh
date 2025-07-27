#!/bin/bash
# Local documentation server for testing API docs
# Usage: ./scripts/serve-docs.sh [port]

set -e

PORT=${1:-8080}
DOCS_DIR="docs"

echo "🚀 Starting local documentation server..."

# Check if docs directory exists
if [ ! -d "$DOCS_DIR" ]; then
    echo "❌ Error: docs directory not found!"
    echo "Please run this script from the project root directory."
    exit 1
fi

# Function to cleanup on exit
cleanup() {
    echo -e "\n🛑 Shutting down documentation server..."
    if [ ! -z "$SERVER_PID" ]; then
        kill $SERVER_PID 2>/dev/null || true
    fi
    exit 0
}

# Setup cleanup trap
trap cleanup SIGINT SIGTERM

# Check if API documentation generator exists and is built
if [ -f "scripts/generate-api-docs.zig" ] && [ ! -f "generate-api-docs" ]; then
    echo "🔨 Building API documentation generator..."
    
    # Check if zig is available
    if ! command -v zig &> /dev/null; then
        echo "⚠️  Warning: Zig not found. Cannot generate docs from source."
        echo "   Install Zig or use existing documentation files."
    else
        zig build-exe scripts/generate-api-docs.zig -O ReleaseFast
        echo "✅ API documentation generator built"
    fi
fi

# Generate fresh documentation if possible
if [ -f "generate-api-docs" ]; then
    echo "📚 Generating fresh API documentation from source..."
    ./generate-api-docs src docs/api-reference-generated.json
    echo "✅ Fresh documentation generated"
fi

# Ensure required files exist
if [ ! -f "$DOCS_DIR/api-reference.yaml" ]; then
    echo "⚠️  Warning: api-reference.yaml not found"
fi

if [ ! -f "$DOCS_DIR/api-docs-interactive.html" ]; then
    echo "⚠️  Warning: api-docs-interactive.html not found"
fi

echo "📁 Serving documentation from: $DOCS_DIR"
echo "🌐 Local server URL: http://localhost:$PORT"
echo ""
echo "Available documentation:"
echo "  📖 Documentation Hub: http://localhost:$PORT/"
echo "  ⚡ Interactive API Docs: http://localhost:$PORT/api-docs-interactive.html"
echo "  📚 Standard API Reference: http://localhost:$PORT/api-reference.html"
if [ -f "$DOCS_DIR/api-reference-generated.html" ]; then
    echo "  🤖 Auto-Generated Docs: http://localhost:$PORT/api-reference-generated.html"
fi
echo ""
echo "Press Ctrl+C to stop the server"

# Try different server options based on what's available
cd "$DOCS_DIR"

if command -v python3 &> /dev/null; then
    echo "🐍 Starting Python HTTP server..."
    python3 -m http.server $PORT &
    SERVER_PID=$!
elif command -v python &> /dev/null; then
    echo "🐍 Starting Python HTTP server..."
    python -m SimpleHTTPServer $PORT &
    SERVER_PID=$!
elif command -v node &> /dev/null; then
    echo "🟢 Starting Node.js HTTP server..."
    npx serve -l $PORT . &
    SERVER_PID=$!
elif command -v php &> /dev/null; then
    echo "🐘 Starting PHP development server..."
    php -S localhost:$PORT &
    SERVER_PID=$!
else
    echo "❌ Error: No suitable HTTP server found!"
    echo "Please install one of the following:"
    echo "  - Python 3 (recommended)"
    echo "  - Node.js with npx"
    echo "  - PHP"
    exit 1
fi

# Wait for server to start
sleep 2

# Try to open browser (optional)
if command -v xdg-open &> /dev/null; then
    xdg-open "http://localhost:$PORT" &>/dev/null &
elif command -v open &> /dev/null; then
    open "http://localhost:$PORT" &>/dev/null &
fi

# Monitor server and handle auto-refresh
LAST_MODIFIED=0
echo "🔄 Monitoring source files for changes..."

while true do
    sleep 5
    
    # Check if source files have changed
    if [ -d "../src" ]; then
        CURRENT_MODIFIED=$(find ../src -name "*.zig" -type f -printf '%T@\n' | sort -n | tail -1)
        
        if [ "$CURRENT_MODIFIED" != "$LAST_MODIFIED" ] && [ "$LAST_MODIFIED" != "0" ]; then
            echo "🔄 Source code changes detected, regenerating documentation..."
            
            if [ -f "../generate-api-docs" ]; then
                ../generate-api-docs ../src api-reference-generated.json
                echo "✅ Documentation updated"
            fi
        fi
        
        LAST_MODIFIED=$CURRENT_MODIFIED
    fi
    
    # Check if server is still running
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "❌ Server process died unexpectedly"
        exit 1
    fi
done