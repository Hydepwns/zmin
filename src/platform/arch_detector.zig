//! Hardware Architecture Detection and Capabilities
//! 
//! This module provides cross-platform hardware capability detection
//! and abstracts architecture differences for optimal performance.
//!
//! Supported Architectures:
//! - x86_64: AVX, AVX2, AVX-512, BMI, BMI2, POPCNT
//! - ARM64: NEON, SVE, SVE2, Crypto extensions
//! - Apple Silicon: AMX, specialized optimizations
//! - Generic: Fallback implementations

const std = @import("std");
const builtin = @import("builtin");

/// Hardware capabilities structure
pub const HardwareCapabilities = struct {
    // Architecture identification
    arch_type: ArchType,
    
    // SIMD capabilities
    has_simd: bool = false,
    vector_width: u16 = 16,
    
    // x86_64 specific
    has_sse2: bool = false,
    has_sse42: bool = false,
    has_avx: bool = false,
    has_avx2: bool = false,
    has_avx512: bool = false,
    has_avx512f: bool = false,
    has_avx512bw: bool = false,
    has_bmi: bool = false,
    has_bmi2: bool = false,
    has_popcnt: bool = false,
    
    // ARM64 specific
    has_neon: bool = false,
    has_sve: bool = false,
    has_sve2: bool = false,
    has_crypto: bool = false,
    
    // Apple Silicon specific
    has_amx: bool = false,
    
    // System information
    cpu_count: u32 = 1,
    cache_line_size: u16 = 64,
    l1_cache_size: u32 = 32 * 1024,    // 32KB
    l2_cache_size: u32 = 256 * 1024,   // 256KB
    l3_cache_size: u32 = 8 * 1024 * 1024, // 8MB
    
    /// Get the best SIMD instruction set available
    pub fn getBestSIMD(self: *const HardwareCapabilities) SIMDType {
        if (self.has_avx512bw) return .avx512;
        if (self.has_avx2) return .avx2;
        if (self.has_avx) return .avx;
        if (self.has_sse42) return .sse42;
        if (self.has_sse2) return .sse2;
        if (self.has_neon) return .neon;
        return .none;
    }
    
    /// Calculate theoretical memory bandwidth
    pub fn getTheoreticalMemoryBandwidth(self: *const HardwareCapabilities) f64 {
        // Rough estimates based on architecture
        return switch (self.arch_type) {
            .x86_64 => if (self.has_avx512) 100.0 else if (self.has_avx2) 60.0 else 30.0, // GB/s
            .arm64 => 50.0, // GB/s
            .apple_silicon => 80.0, // GB/s - unified memory architecture
            .other => 20.0, // GB/s
        };
    }
    
    /// Get optimal chunk size for processing
    pub fn getOptimalChunkSize(self: *const HardwareCapabilities) usize {
        // Base on L2 cache size to minimize cache misses
        return @min(self.l2_cache_size / 2, 64 * 1024);
    }
};

/// Architecture types
pub const ArchType = enum {
    x86_64,
    arm64,
    apple_silicon,
    other,
};

/// SIMD instruction set types
pub const SIMDType = enum {
    none,
    sse2,
    sse42,
    avx,
    avx2,
    avx512,
    neon,
    sve,
    sve2,
};

/// Detect hardware capabilities
pub fn detectCapabilities() HardwareCapabilities {
    var caps = HardwareCapabilities{
        .arch_type = detectArchitecture(),
    };
    
    // Detect CPU count
    caps.cpu_count = @intCast(std.Thread.getCpuCount() catch 1);
    
    // Architecture-specific capability detection
    switch (caps.arch_type) {
        .x86_64 => detectX86Capabilities(&caps),
        .arm64 => detectARM64Capabilities(&caps),
        .apple_silicon => detectAppleSiliconCapabilities(&caps),
        .other => detectGenericCapabilities(&caps),
    }
    
    // Set SIMD flag and vector width
    caps.has_simd = caps.getBestSIMD() != .none;
    caps.vector_width = getSIMDVectorWidth(caps.getBestSIMD());
    
    return caps;
}

/// Detect base architecture
fn detectArchitecture() ArchType {
    return switch (builtin.cpu.arch) {
        .x86_64 => .x86_64,
        .aarch64 => {
            // Distinguish Apple Silicon from generic ARM64
            if (builtin.os.tag == .macos) {
                return .apple_silicon;
            }
            return .arm64;
        },
        else => .other,
    };
}

/// Detect x86_64 specific capabilities
fn detectX86Capabilities(caps: *HardwareCapabilities) void {
    if (builtin.cpu.arch != .x86_64) return;
    
    // Use Zig's built-in CPU feature detection
    caps.has_sse2 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse2);
    caps.has_sse42 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_2);
    caps.has_avx = std.Target.x86.featureSetHas(builtin.cpu.features, .avx);
    caps.has_avx2 = std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);
    caps.has_avx512f = std.Target.x86.featureSetHas(builtin.cpu.features, .avx512f);
    caps.has_avx512bw = std.Target.x86.featureSetHas(builtin.cpu.features, .avx512bw);
    caps.has_bmi = std.Target.x86.featureSetHas(builtin.cpu.features, .bmi);
    caps.has_bmi2 = std.Target.x86.featureSetHas(builtin.cpu.features, .bmi2);
    caps.has_popcnt = std.Target.x86.featureSetHas(builtin.cpu.features, .popcnt);
    
    // Set AVX-512 flag if both F and BW are available
    caps.has_avx512 = caps.has_avx512f and caps.has_avx512bw;
    
    // Estimate cache sizes based on common x86_64 configurations
    if (caps.has_avx512) {
        // High-end server/workstation
        caps.l1_cache_size = 64 * 1024;
        caps.l2_cache_size = 1024 * 1024;
        caps.l3_cache_size = 16 * 1024 * 1024;
    } else if (caps.has_avx2) {
        // Modern consumer CPU
        caps.l1_cache_size = 32 * 1024;
        caps.l2_cache_size = 256 * 1024;
        caps.l3_cache_size = 8 * 1024 * 1024;
    }
}

/// Detect ARM64 specific capabilities
fn detectARM64Capabilities(caps: *HardwareCapabilities) void {
    if (builtin.cpu.arch != .aarch64) return;
    
    // Use Zig's built-in CPU feature detection
    caps.has_neon = std.Target.aarch64.featureSetHas(builtin.cpu.features, .neon);
    caps.has_sve = std.Target.aarch64.featureSetHas(builtin.cpu.features, .sve);
    caps.has_sve2 = std.Target.aarch64.featureSetHas(builtin.cpu.features, .sve2);
    caps.has_crypto = std.Target.aarch64.featureSetHas(builtin.cpu.features, .crypto);
    
    // ARM64 typically has 128-bit NEON
    caps.vector_width = if (caps.has_neon) 16 else 8;
    
    // Typical ARM64 cache configuration
    caps.l1_cache_size = 64 * 1024;
    caps.l2_cache_size = 512 * 1024;
    caps.l3_cache_size = 4 * 1024 * 1024;
}

/// Detect Apple Silicon specific capabilities
fn detectAppleSiliconCapabilities(caps: *HardwareCapabilities) void {
    // First detect ARM64 capabilities
    detectARM64Capabilities(caps);
    
    // Apple Silicon specific features
    if (builtin.os.tag == .macos and builtin.cpu.arch == .aarch64) {
        caps.has_amx = true; // Assume AMX is available on Apple Silicon
        
        // Apple Silicon has larger caches and unified memory
        caps.l1_cache_size = 128 * 1024;
        caps.l2_cache_size = 12 * 1024 * 1024; // Large L2 cache
        caps.l3_cache_size = 0; // Unified memory architecture
        caps.cache_line_size = 128; // Larger cache lines
    }
}

/// Detect generic capabilities (fallback)
fn detectGenericCapabilities(caps: *HardwareCapabilities) void {
    // Conservative defaults for unknown architectures
    caps.has_simd = false;
    caps.vector_width = 8;
    caps.l1_cache_size = 16 * 1024;
    caps.l2_cache_size = 128 * 1024;
    caps.l3_cache_size = 2 * 1024 * 1024;
}

/// Get vector width for SIMD type
fn getSIMDVectorWidth(simd_type: SIMDType) u16 {
    return switch (simd_type) {
        .none => 1,
        .sse2, .sse42 => 16,  // 128-bit
        .avx => 32,           // 256-bit
        .avx2 => 32,          // 256-bit
        .avx512 => 64,        // 512-bit
        .neon => 16,          // 128-bit
        .sve => 16,           // Variable, default to 128-bit
        .sve2 => 16,          // Variable, default to 128-bit
    };
}

/// Runtime CPU feature detection using CPUID (x86_64 only)
pub fn detectCPUIDFeatures() ?X86Features {
    if (builtin.cpu.arch != .x86_64) return null;
    
    // This would contain actual CPUID instruction calls
    // For now, use compile-time detection
    return X86Features{
        .has_sse2 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse2),
        .has_avx = std.Target.x86.featureSetHas(builtin.cpu.features, .avx),
        .has_avx2 = std.Target.x86.featureSetHas(builtin.cpu.features, .avx2),
        .has_avx512f = std.Target.x86.featureSetHas(builtin.cpu.features, .avx512f),
        .has_bmi2 = std.Target.x86.featureSetHas(builtin.cpu.features, .bmi2),
    };
}

/// x86_64 specific features structure
pub const X86Features = struct {
    has_sse2: bool,
    has_avx: bool,
    has_avx2: bool,
    has_avx512f: bool,
    has_bmi2: bool,
};

/// Get optimal number of threads for parallel processing
pub fn getOptimalThreadCount(caps: *const HardwareCapabilities) u32 {
    // Use all available cores, but cap at reasonable limit
    return @min(caps.cpu_count, 16);
}

/// Get memory alignment requirement for optimal SIMD performance
pub fn getOptimalAlignment(caps: *const HardwareCapabilities) u16 {
    return switch (caps.getBestSIMD()) {
        .avx512 => 64,  // 512-bit alignment
        .avx, .avx2 => 32,  // 256-bit alignment
        .sse2, .sse42, .neon => 16,  // 128-bit alignment
        else => 8,  // Default alignment
    };
}

/// Check if specific instruction set is available
pub fn hasInstructionSet(caps: *const HardwareCapabilities, instruction_set: SIMDType) bool {
    return switch (instruction_set) {
        .none => true,
        .sse2 => caps.has_sse2,
        .sse42 => caps.has_sse42,
        .avx => caps.has_avx,
        .avx2 => caps.has_avx2,
        .avx512 => caps.has_avx512,
        .neon => caps.has_neon,
        .sve => caps.has_sve,
        .sve2 => caps.has_sve2,
    };
}

/// Platform-specific optimizations availability
pub const PlatformOptimizations = struct {
    has_huge_pages: bool,
    has_numa: bool,
    has_io_uring: bool,
    has_hardware_counters: bool,
    
    pub fn detect() PlatformOptimizations {
        return PlatformOptimizations{
            .has_huge_pages = detectHugePages(),
            .has_numa = detectNUMA(),
            .has_io_uring = detectIOUring(),
            .has_hardware_counters = detectHardwareCounters(),
        };
    }
    
    fn detectHugePages() bool {
        return switch (builtin.os.tag) {
            .linux => true,  // Linux supports huge pages
            .windows => true, // Windows supports large pages
            else => false,
        };
    }
    
    fn detectNUMA() bool {
        return switch (builtin.os.tag) {
            .linux => true,  // Linux has NUMA support
            .windows => true, // Windows has NUMA support
            else => false,
        };
    }
    
    fn detectIOUring() bool {
        return builtin.os.tag == .linux; // io_uring is Linux-specific
    }
    
    fn detectHardwareCounters() bool {
        return switch (builtin.os.tag) {
            .linux => true,  // Linux perf counters
            .windows => true, // Windows PMC
            .macos => false,  // Limited access on macOS
            else => false,
        };
    }
};

/// Print detailed hardware capabilities (for debugging)
pub fn printCapabilities(caps: *const HardwareCapabilities) void {
    std.debug.print("Hardware Capabilities:\n");
    std.debug.print("  Architecture: {}\n", .{caps.arch_type});
    std.debug.print("  CPU Count: {}\n", .{caps.cpu_count});
    std.debug.print("  Vector Width: {} bytes\n", .{caps.vector_width});
    std.debug.print("  Best SIMD: {}\n", .{caps.getBestSIMD()});
    
    if (caps.arch_type == .x86_64) {
        std.debug.print("  x86_64 Features:\n");
        std.debug.print("    SSE2: {}\n", .{caps.has_sse2});
        std.debug.print("    AVX: {}\n", .{caps.has_avx});
        std.debug.print("    AVX2: {}\n", .{caps.has_avx2});
        std.debug.print("    AVX-512: {}\n", .{caps.has_avx512});
        std.debug.print("    BMI2: {}\n", .{caps.has_bmi2});
    }
    
    if (caps.arch_type == .arm64 or caps.arch_type == .apple_silicon) {
        std.debug.print("  ARM64 Features:\n");
        std.debug.print("    NEON: {}\n", .{caps.has_neon});
        std.debug.print("    SVE: {}\n", .{caps.has_sve});
        std.debug.print("    Crypto: {}\n", .{caps.has_crypto});
        
        if (caps.arch_type == .apple_silicon) {
            std.debug.print("    AMX: {}\n", .{caps.has_amx});
        }
    }
    
    std.debug.print("  Cache Sizes:\n");
    std.debug.print("    L1: {} KB\n", .{caps.l1_cache_size / 1024});
    std.debug.print("    L2: {} KB\n", .{caps.l2_cache_size / 1024});
    std.debug.print("    L3: {} KB\n", .{caps.l3_cache_size / 1024});
    std.debug.print("  Theoretical Memory BW: {d:.1} GB/s\n", .{caps.getTheoreticalMemoryBandwidth()});
}