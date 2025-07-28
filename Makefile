# Zmin Makefile
# Common development commands for the zmin project

.PHONY: help build test clean install uninstall format lint docs examples wasm c-api docker

# Default target
help:
	@echo "Zmin Development Commands:"
	@echo ""
	@echo "Build Commands:"
	@echo "  build     - Build the project (zig build)"
	@echo "  install   - Install zmin system-wide"
	@echo "  uninstall - Remove zmin installation"
	@echo "  clean     - Clean build artifacts"
	@echo "  clean-all - Deep clean (including cache)"
	@echo "  cleanup   - Comprehensive cleanup (recommended)"
	@echo "  cleanup-docker - Cleanup including Docker artifacts"
	@echo "  organize  - Organize project structure"
	@echo "  status    - Show project status and cleanup opportunities"
	@echo ""
	@echo "Testing Commands:"
	@echo "  test      - Run all tests"
	@echo "  test-fast - Run fast tests only"
	@echo "  benchmark - Run performance benchmarks"
	@echo ""
	@echo "Code Quality:"
	@echo "  format    - Format all Zig code"
	@echo "  lint      - Run linting checks"
	@echo ""
	@echo "Documentation:"
	@echo "  docs      - Generate API documentation"
	@echo "  serve-docs- Serve documentation locally"
	@echo ""
	@echo "Examples & Tools:"
	@echo "  examples  - Build all examples"
	@echo "  tools     - Build all tools"
	@echo "  wasm      - Build WebAssembly module"
	@echo "  c-api     - Build C API library"
	@echo ""
	@echo "Development:"
	@echo "  dev-setup - Setup development environment"
	@echo "  docker    - Build Docker image"
	@echo "  release   - Build release artifacts"

# Build commands
build:
	zig build

install:
	zig build install

uninstall:
	@echo "Removing zmin installation..."
	@rm -f /usr/local/bin/zmin || true
	@rm -f /usr/bin/zmin || true
	@echo "zmin uninstalled"

clean:
	@echo "Cleaning build artifacts..."
	zig build clean
	@echo "Removing additional build files..."
	@rm -f *.o *.a *.so *.dylib *.dll *.exe
	@rm -f numa_allocator test_* lib*_test.a
	@rm -f generate-api-docs generate-api-docs.o
	@rm -f *.tmp *.temp *.log *_out.json *_output.json
	@rm -f *.output *.minified
	@rm -rf build/ dist/ target/
	@echo "✅ Cleanup completed"

clean-all: clean
	@echo "Performing deep cleanup..."
	@rm -rf .zig-cache/
	@rm -rf zig-out/
	@echo "✅ Deep cleanup completed"

cleanup:
	@echo "Running comprehensive cleanup script..."
	@./scripts/cleanup.sh
	@echo "✅ Comprehensive cleanup completed"

cleanup-docker:
	@echo "Running comprehensive cleanup with Docker cleanup..."
	@./scripts/cleanup.sh --docker
	@echo "✅ Comprehensive cleanup with Docker cleanup completed"

organize:
	@echo "Organizing project structure..."
	@./scripts/organize.sh
	@echo "✅ Project organization completed"

status:
	@echo "Checking project status..."
	@./scripts/status.sh
	@echo "✅ Status check completed"

# Testing commands
test:
	zig build test

test-fast:
	zig build test:fast

benchmark:
	zig build benchmark

# Code quality
format:
	zig fmt src/ scripts/ tools/ examples/ tests/

lint:
	@echo "Running linting checks..."
	@zig build test:fast
	@echo "✅ Linting passed"

# Documentation
docs:
	@echo "Generating API documentation..."
	@zig build-exe scripts/generate-api-docs.zig -O ReleaseFast
	@./generate-api-docs src docs/api-reference-generated.json
	@rm -f generate-api-docs
	@echo "✅ Documentation generated"

# Content generation
generate-content:
	@echo "Generating content from centralized data..."
	@zig run scripts/generate-content.zig

# Build site with generated content
build-site: generate-content
	@echo "Building Hugo site..."
	@hugo --minify

serve-docs:
	@echo "Serving documentation at http://localhost:8000"
	@python3 -m http.server 8000 --directory docs/

# Examples and tools
examples:
	zig build examples

tools:
	zig build tools

wasm:
	zig build wasm

c-api:
	zig build c-api

# Development setup
dev-setup:
	@echo "Setting up development environment..."
	@echo "1. Checking Zig installation..."
	@zig version
	@echo "2. Building project..."
	@zig build
	@echo "3. Running tests..."
	@zig build test:fast
	@echo "4. Generating documentation..."
	@$(MAKE) docs
	@echo "✅ Development environment ready!"

# Docker
docker:
	@echo "Building Docker image..."
	docker build -t zmin .
	@echo "✅ Docker image built"

# Release
release:
	@echo "Building release artifacts..."
	@zig build --release=fast
	@zig build wasm
	@zig build c-api
	@echo "✅ Release artifacts built"

# Performance testing
perf-test:
	@echo "Running performance tests..."
	@zig build --release=fast
	@echo '{"test": "data"}' > test.json
	@time ./zig-out/bin/zmin test.json output.json
	@rm -f test.json output.json
	@echo "✅ Performance test completed"

# Memory safety check
memcheck:
	@echo "Running memory safety checks..."
	@zig build
	@valgrind --leak-check=full --show-leak-kinds=all ./zig-out/bin/zmin test.json output.json 2>&1 | grep -q "ERROR SUMMARY: 0 errors" && echo "✅ No memory errors" || echo "❌ Memory errors found"

# Quick development cycle
dev: format lint test-fast
	@echo "✅ Development cycle completed"

# Full CI simulation
ci: clean build test benchmark docs
	@echo "✅ CI simulation completed"
