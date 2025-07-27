---
title: "Installation"
date: 2024-01-01
draft: false
weight: 2
---

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
git clone https://github.com/hydepwns/zmin.git
cd zmin
zig build --release=fast --release=fast

# Install system-wide (optional)
sudo cp zig-out/bin/zmin /usr/local/bin/
```

### macOS

```bash
# Install Zig using Homebrew
brew install zig

# Clone and build zmin
git clone https://github.com/hydepwns/zmin.git
cd zmin
zig build --release=fast --release=fast

# Install to /usr/local/bin (optional)
sudo cp zig-out/bin/zmin /usr/local/bin/
```

### Windows

```powershell
# Download Zig from https://ziglang.org/download/
# Extract and add to PATH

# Clone and build zmin
git clone https://github.com/hydepwns/zmin.git
cd zmin
zig build --release=fast --release=fast

# The executable will be at zig-out\bin\zmin.exe
```

## Package Managers

### Homebrew (macOS/Linux)

```bash
# Coming soon
brew tap hydepwns/zmin
brew install zmin
```

### APT (Debian/Ubuntu)

```bash
# Coming soon
sudo add-apt-repository ppa:hydepwns/zmin
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
docker pull hydepwns/zmin:latest

# Run zmin in container
docker run -v $(pwd):/data hydepwns/zmin /data/input.json /data/output.json
```

### Building Docker Image

```bash
# Clone repository
git clone https://github.com/hydepwns/zmin.git
cd zmin

# Build Docker image
docker build -t zmin .

# Run container
docker run -v $(pwd):/data zmin /data/input.json /data/output.json
```

## Verification

Test your installation:

```bash
# Check version
zmin --version

# Test basic functionality
echo '{"test": "data"}' | zmin

# Expected output: {"test":"data"}
```

## Troubleshooting

### Common Issues

1. **Zig not found**: Ensure Zig is in your PATH
2. **Permission denied**: Use `sudo` for system-wide installation
3. **Build fails**: Check Zig version compatibility
4. **GPU not detected**: Install appropriate GPU drivers

### Getting Help

- [GitHub Issues](https://github.com/hydepwns/zmin/issues)
- [Documentation](/docs/)
- [Discord Community](https://discord.gg/zmin)
