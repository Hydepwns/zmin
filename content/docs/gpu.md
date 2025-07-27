---
title: "GPU Acceleration Guide"
date: 2024-01-01
draft: false
weight: 8
---


zmin can leverage GPU acceleration for massive JSON datasets, providing 2-5x performance improvements over CPU-only processing.

## Overview

GPU acceleration in zmin supports:
- **CUDA**: NVIDIA GPUs (GTX 10-series or newer)
- **OpenCL**: Cross-platform GPU support (NVIDIA, AMD, Intel)
- **Auto-detection**: Automatically selects the best available GPU

## Quick Start

### Check GPU Support

```bash
# Check available GPUs
zmin --gpu-info

# Sample output:
# ═══════════════════════════════════════
# GPU Acceleration Support
# ═══════════════════════════════════════
# CUDA: Available (Driver 12.2)
#   - Device 0: GeForce RTX 4090 (16GB)
#   - Device 1: GeForce RTX 3080 (10GB)
# OpenCL: Available
#   - Platform 0: NVIDIA CUDA
#   - Platform 1: Intel OpenCL
# ═══════════════════════════════════════
```

### Basic GPU Usage

```bash
# Automatic GPU selection
zmin --gpu auto large-file.json output.json

# Use specific GPU backend
zmin --gpu cuda large-file.json output.json
zmin --gpu opencl large-file.json output.json

# Use specific device
zmin --gpu cuda:0 large-file.json output.json
```

## Installation

### CUDA Support

#### Prerequisites
- NVIDIA GPU (Compute Capability 6.0+)
- CUDA Toolkit 11.0 or later
- NVIDIA Driver 470+ or compatible

#### Installation Steps

```bash
# 1. Install CUDA Toolkit
# Ubuntu/Debian
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb
sudo dpkg -i cuda-keyring_1.0-1_all.deb
sudo apt-get update
sudo apt-get install cuda-toolkit-12-2

# CentOS/RHEL
sudo dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel8/x86_64/cuda-rhel8.repo
sudo dnf install cuda-toolkit-12-2

# 2. Build zmin with CUDA support
git clone https://github.com/hydepwns/zmin
cd zmin
zig build --release=fast -Dgpu=cuda

# 3. Verify installation
./zig-out/bin/zmin --gpu-info
```

#### Docker with CUDA

```dockerfile
FROM nvidia/cuda:12.2-devel-ubuntu20.04

# Install Zig
RUN wget https://ziglang.org/download/0.14.1/zig-linux-x86_64-0.14.1.tar.xz && \
    tar -xf zig-linux-x86_64-0.14.1.tar.xz && \
    mv zig-linux-x86_64-0.14.1 /usr/local/zig

ENV PATH="/usr/local/zig:${PATH}"

# Build zmin with CUDA
COPY . /zmin
WORKDIR /zmin
RUN zig build --release=fast -Dgpu=cuda

ENTRYPOINT ["./zig-out/bin/zmin"]
```

```bash
# Run with GPU access
docker run --gpus all -v $(pwd):/data zmin-cuda --gpu cuda /data/input.json /data/output.json
```

### OpenCL Support

#### Prerequisites
- OpenCL 1.2 or later
- GPU drivers with OpenCL support

#### Installation Steps

```bash
# Ubuntu/Debian
sudo apt-get install opencl-headers ocl-icd-opencl-dev

# Install GPU-specific drivers
# NVIDIA
sudo apt-get install nvidia-opencl-dev

# AMD
sudo apt-get install mesa-opencl-icd

# Intel
sudo apt-get install intel-opencl-icd

# Build zmin with OpenCL
zig build --release=fast -Dgpu=opencl

# Test installation
zmin --gpu-info
```

## Performance Characteristics

### When to Use GPU Acceleration

**Best for**:
- Files > 100MB
- Batch processing multiple files
- Repetitive minification tasks
- High-throughput scenarios

**Not optimal for**:
- Small files (< 10MB)
- One-off processing
- Memory-constrained environments

### Performance Comparison

| File Size | CPU (Turbo) | CUDA | OpenCL | Speedup |
|-----------|-------------|------|--------|---------|
| 10 MB | 555 MB/s | 450 MB/s | 400 MB/s | 0.8x |
| 100 MB | 1.1 GB/s | 2.2 GB/s | 1.8 GB/s | 2.0x |
| 1 GB | 1.0 GB/s | 3.5 GB/s | 2.8 GB/s | 3.5x |
| 10 GB | 900 MB/s | 4.2 GB/s | 3.2 GB/s | 4.7x |

## GPU Architecture

### CUDA Implementation

```
┌─────────────────────────────────────────────────────────────┐
│                    Host (CPU) Memory                        │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │   Input JSON    │───▶│  Preprocessor   │                 │
│  └─────────────────┘    └─────────────────┘                 │
└─────────────────────────────────┬───────────────────────────┘
                                  │ PCIe Transfer
┌─────────────────────────────────▼───────────────────────────┐
│                   Device (GPU) Memory                       │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │   Input Buffer  │───▶│  CUDA Kernels   │                 │
│  └─────────────────┘    └─────────────────┘                 │
│                                  │                          │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │  Output Buffer  │◀───│   Minification  │                 │
│  └─────────────────┘    └─────────────────┘                 │
└─────────────────────────────────┬───────────────────────────┘
                                  │ PCIe Transfer
┌─────────────────────────────────▼───────────────────────────┐
│                    Host (CPU) Memory                        │
│  ┌─────────────────┐    ┌─────────────────┐                 │
│  │  Final Output   │◀───│  Postprocessor  │                 │
│  └─────────────────┘    └─────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
```

### Parallel Processing Strategy

zmin uses a multi-stage GPU pipeline:

1. **Chunking**: Split large JSON into processable chunks
2. **Transfer**: Copy data to GPU memory
3. **Parse**: Parallel JSON parsing on GPU
4. **Minify**: Remove whitespace in parallel
5. **Merge**: Combine results on GPU
6. **Transfer**: Copy results back to CPU

## Configuration

### GPU Settings

```json
{
  "gpu": {
    "enabled": true,
    "backend": "auto",
    "device_id": 0,
    "memory_limit": "8GB",
    "chunk_size": "64MB",
    "parallel_streams": 4,
    "optimization_level": "aggressive"
  }
}
```

### Environment Variables

```bash
# Force specific GPU backend
export ZMIN_GPU_BACKEND=cuda

# Set memory limit
export ZMIN_GPU_MEMORY_LIMIT=4096M

# Enable GPU debugging
export ZMIN_GPU_DEBUG=1

# Disable GPU auto-detection
export ZMIN_GPU_FORCE_CPU=1
```

## Advanced Usage

### Batch Processing

```bash
# Process multiple files on GPU
find /data -name "*.json" | \
parallel -j1 zmin --gpu cuda {} {.}.min.json

# Or use built-in batch mode
zmin --gpu cuda --batch /data/*.json --output-dir /processed/
```

### Streaming Large Files

```bash
# Stream processing for files larger than GPU memory
cat huge-file.json | zmin --gpu cuda --stream > output.json

# With progress monitoring
pv huge-file.json | zmin --gpu cuda --stream --progress > output.json
```

### Custom Memory Management

```bash
# Limit GPU memory usage
zmin --gpu cuda --gpu-memory 4G large-file.json output.json

# Use memory mapping for very large files
zmin --gpu cuda --mmap huge-file.json output.json

# Optimize for memory-constrained GPUs
zmin --gpu cuda --chunk-size 32M --streams 2 large-file.json output.json
```

## Optimization Tips

### Memory Optimization

```bash
# Reduce chunk size for low-memory GPUs
zmin --gpu cuda --chunk-size 16M input.json output.json

# Use compression for transfers
zmin --gpu cuda --compress-transfers input.json output.json

# Profile memory usage
zmin --gpu cuda --profile-memory large-file.json output.json
```

### Performance Tuning

```bash
# Increase parallel streams for high-end GPUs
zmin --gpu cuda --streams 8 input.json output.json

# Use pinned memory for faster transfers
zmin --gpu cuda --pinned-memory input.json output.json

# Optimize for specific GPU architecture
zmin --gpu cuda --arch=sm_86 input.json output.json
```

## Monitoring and Debugging

### Performance Monitoring

```bash
# Real-time GPU monitoring
zmin --gpu cuda --monitor input.json output.json

# Sample output:
# ═══════════════════════════════════════
# GPU Performance Monitor
# ═══════════════════════════════════════
# GPU Utilization: 95%
# Memory Usage: 6.2GB / 16GB (39%)
# Temperature: 72°C
# Power Usage: 280W / 350W
# Transfer Rate: 12.5 GB/s
# Processing Rate: 3.2 GB/s
# ═══════════════════════════════════════
```

### Debug Information

```bash
# Enable verbose GPU logging
ZMIN_GPU_DEBUG=1 zmin --gpu cuda --verbose input.json output.json

# Profile GPU kernels
zmin --gpu cuda --profile-kernels input.json output.json

# Memory usage analysis
zmin --gpu cuda --analyze-memory input.json output.json
```

### NVIDIA Profiling Tools

```bash
# Use nvprof for detailed analysis
nvprof zmin --gpu cuda large-file.json output.json

# Use Nsight Systems
nsys profile zmin --gpu cuda large-file.json output.json

# Use Nsight Compute for kernel analysis
ncu --set full zmin --gpu cuda large-file.json output.json
```

## Troubleshooting

### Common Issues

#### GPU Not Detected

**Check GPU availability**:
```bash
# NVIDIA
nvidia-smi

# OpenCL
clinfo

# zmin detection
zmin --gpu-info
```

**Solutions**:
```bash
# Update drivers
sudo ubuntu-drivers autoinstall

# Verify CUDA installation
nvcc --version

# Check OpenCL
apt list --installed | grep opencl
```

#### Out of Memory Errors

**Reduce memory usage**:
```bash
# Smaller chunks
zmin --gpu cuda --chunk-size 16M input.json output.json

# Lower precision (if supported)
zmin --gpu cuda --half-precision input.json output.json

# Use CPU fallback for large sections
zmin --gpu cuda --hybrid-mode input.json output.json
```

#### Slow Performance

**Optimization checklist**:
```bash
# Check GPU utilization
nvidia-smi

# Verify PCIe bandwidth
nvidia-smi topo -m

# Test memory bandwidth
zmin --gpu cuda --benchmark-memory

# Profile bottlenecks
zmin --gpu cuda --profile input.json output.json
```

### Error Codes

- **GPU_NOT_FOUND (201)**: No compatible GPU detected
- **GPU_MEMORY_ERROR (202)**: Insufficient GPU memory
- **GPU_KERNEL_ERROR (203)**: GPU kernel execution failed
- **GPU_TRANSFER_ERROR (204)**: Data transfer failed
- **GPU_DRIVER_ERROR (205)**: GPU driver incompatible

## Platform-Specific Notes

### Windows

```powershell
# Install CUDA
# Download from NVIDIA website
# https://developer.nvidia.com/cuda-downloads

# Build with Visual Studio
zig build --release=fast -Dgpu=cuda -Dtarget=x86_64-windows-msvc

# Set CUDA path
$env:CUDA_PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.2"
```

### macOS

```bash
# OpenCL only (CUDA not supported on macOS)
zig build --release=fast -Dgpu=opencl

# Use Metal Performance Shaders (future support)
zig build --release=fast -Dgpu=metal
```

### Linux Containers

```yaml
# Docker Compose with GPU
version: '3.8'
services:
  zmin:
    image: zmin:cuda
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    volumes:
      - ./data:/data
    command: --gpu cuda /data/input.json /data/output.json
```

## Benchmarking

### GPU Benchmark Suite

```bash
# Run comprehensive GPU benchmarks
zmin --gpu cuda --benchmark-suite

# Custom benchmark
zmin --gpu cuda --benchmark \
  --file-sizes 1M,10M,100M,1G \
  --chunk-sizes 16M,32M,64M \
  --streams 1,2,4,8 \
  --output benchmark-results.json
```

### Performance Regression Testing

```bash
#!/bin/bash
# gpu-benchmark.sh

# Baseline performance test
baseline_perf=$(zmin --gpu cuda --benchmark-quick large-file.json 2>&1 | grep "Throughput" | awk '{print $2}')

# Compare with CPU
cpu_perf=$(zmin --mode turbo large-file.json /dev/null 2>&1 | grep "Throughput" | awk '{print $2}')

speedup=$(echo "scale=2; $baseline_perf / $cpu_perf" | bc)
echo "GPU Speedup: ${speedup}x"

if (( $(echo "$speedup < 2.0" | bc -l) )); then
    echo "Warning: GPU performance below expected threshold"
    exit 1
fi
```

## Future Enhancements

### Roadmap

- **Multi-GPU support**: Distribute processing across multiple GPUs
- **AMD ROCm support**: Native AMD GPU acceleration
- **Intel GPU support**: Intel Arc and integrated graphics
- **Apple Metal**: Native acceleration on Apple Silicon
- **WebGPU**: Browser-based GPU acceleration

### Experimental Features

```bash
# Multi-GPU processing (experimental)
zmin --gpu cuda:0,1,2,3 --multi-gpu huge-file.json output.json

# GPU-CPU hybrid processing
zmin --gpu cuda --hybrid-threshold 50M input.json output.json

# Distributed GPU processing
zmin --gpu cuda --distributed --nodes gpu-node1,gpu-node2 input.json output.json
```

For the latest GPU acceleration features and updates, visit [zmin.droo.foo/gpu](https://zmin.droo.foo/gpu).