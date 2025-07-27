# Installation Guide

This guide covers all installation methods for zmin across different platforms.

## Prerequisites

- **Zig Compiler**: Version 0.14.1 or later
- **Git**: For cloning the repository
- **C Compiler**: Optional, for C API bindings

## Building from Source

### Linux

```bash
# Install Zig (if not already installed)
wget https://ziglang.org/download/0.14.1/zig-linux-x86_64-0.14.1.tar.xz
tar -xf zig-linux-x86_64-0.14.1.tar.xz
export PATH=$PATH:$(pwd)/zig-linux-x86_64-0.14.1

# Clone and build zmin
git clone https://github.com/yourusername/zmin.git
cd zmin
zig build --release=fast

# Install system-wide (optional)
sudo cp zig-out/bin/zmin /usr/local/bin/
```

### macOS

```bash
# Install Zig using Homebrew
brew install zig

# Clone and build zmin
git clone https://github.com/yourusername/zmin.git
cd zmin
zig build --release=fast

# Install to /usr/local/bin (optional)
sudo cp zig-out/bin/zmin /usr/local/bin/
```

### Windows

```powershell
# Download Zig from https://ziglang.org/download/
# Extract and add to PATH

# Clone and build zmin
git clone https://github.com/yourusername/zmin.git
cd zmin
zig build --release=fast

# The executable will be at zig-out\bin\zmin.exe
```

## Package Managers

### Homebrew (macOS/Linux)

```bash
# Coming soon
brew tap yourusername/zmin
brew install zmin
```

### APT (Debian/Ubuntu)

```bash
# Coming soon
sudo add-apt-repository ppa:yourusername/zmin
sudo apt update
sudo apt install zmin
```

### AUR (Arch Linux)

```bash
# Coming soon
yay -S zmin
# or
paru -S zmin
```

## Docker

### Using Pre-built Image

```bash
# Pull the image
docker pull yourusername/zmin:latest

# Run zmin in container
docker run -v $(pwd):/data yourusername/zmin /data/input.json /data/output.json
```

### Building Docker Image

```dockerfile
# Dockerfile
FROM alpine:latest AS builder

# Install Zig
RUN apk add --no-cache wget xz
RUN wget https://ziglang.org/download/0.14.1/zig-linux-x86_64-0.14.1.tar.xz && \
    tar -xf zig-linux-x86_64-0.14.1.tar.xz && \
    mv zig-linux-x86_64-0.14.1 /usr/local/zig

ENV PATH="/usr/local/zig:${PATH}"

# Build zmin
WORKDIR /build
COPY . .
RUN zig build --release=fast

# Runtime image
FROM alpine:latest
RUN apk add --no-cache libstdc++
COPY --from=builder /build/zig-out/bin/zmin /usr/local/bin/
ENTRYPOINT ["zmin"]
```

Build and run:

```bash
docker build -t zmin .
docker run -v $(pwd):/data zmin /data/input.json /data/output.json
```

## Binary Releases

Pre-built binaries are available for:

- Linux x86_64
- Linux ARM64
- macOS x86_64 (Intel)
- macOS ARM64 (Apple Silicon)
- Windows x86_64

Download from [GitHub Releases](https://github.com/yourusername/zmin/releases).

### Verify Checksums

```bash
# Download binary and checksum
wget https://github.com/yourusername/zmin/releases/download/v1.0.0/zmin-linux-x64
wget https://github.com/yourusername/zmin/releases/download/v1.0.0/checksums.txt

# Verify
sha256sum -c checksums.txt
```

## Build Options

### Release Modes

```bash
# Debug build (with assertions and debug info)
zig build

# Release-Safe (optimized with safety checks)
zig build --release=safe

# Release-Fast (maximum performance)
zig build --release=fast

# Release-Small (minimum binary size)
zig build --release=small
```

### Feature Flags

```bash
# Disable SIMD optimizations
zig build --release=fast -Dsimd=false

# Enable telemetry (opt-in)
zig build --release=fast -Dtelemetry=true

# Custom allocator backend
zig build --release=fast -Dallocator=jemalloc
```

### Cross-Compilation

```bash
# Linux ARM64
zig build --release=fast -Dtarget=aarch64-linux-gnu

# macOS ARM64
zig build --release=fast -Dtarget=aarch64-macos

# Windows x64
zig build --release=fast -Dtarget=x86_64-windows-gnu
```

## Verification

After installation, verify zmin is working:

```bash
# Check version
zmin --version

# Run a simple test
echo '{"test": "data"}' | zmin

# Expected output: {"test":"data"}
```

## Platform-Specific Notes

### Linux

- Requires glibc 2.17 or later
- For musl-based systems, build with `-Dtarget=x86_64-linux-musl`

### macOS

- Requires macOS 10.15 or later
- Universal binary support coming soon

### Windows

- Requires Windows 10 or later
- Add to PATH for global access

## Troubleshooting Installation

### Zig Not Found

```bash
# Add Zig to PATH
export PATH=$PATH:/path/to/zig

# Or install system-wide
sudo ln -s /path/to/zig/zig /usr/local/bin/zig
```

### Build Errors

```bash
# Clean build cache
rm -rf zig-cache zig-out

# Try debug build first
zig build

# Check Zig version
zig version
```

### Permission Denied

```bash
# Make binary executable
chmod +x ./zig-out/bin/zmin

# Install with proper permissions
sudo install -m 755 ./zig-out/bin/zmin /usr/local/bin/
```

## Uninstallation

### Manual Installation

```bash
# Remove binary
sudo rm /usr/local/bin/zmin

# Remove source directory
rm -rf /path/to/zmin
```

### Package Manager

```bash
# Homebrew
brew uninstall zmin

# APT
sudo apt remove zmin

# Docker
docker rmi yourusername/zmin
```

## Next Steps

- Read [Getting Started](getting-started.md) for basic usage
- Check [Usage Guide](usage.md) for advanced features
- See [Performance Guide](performance.md) for optimization tips
