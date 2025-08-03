//! Unified SIMD Detection Module
//!
//! This module consolidates all CPU feature detection logic into a single,
//! consistent interface used throughout the codebase.

const std = @import("std");
const builtin = @import("builtin");

/// CPU vendor enumeration
pub const CpuVendor = enum {
    intel,
    amd,
    apple,
    arm,
    unknown,
    
    pub fn getName(self: CpuVendor) []const u8 {
        return switch (self) {
            .intel => "Intel",
            .amd => "AMD",
            .apple => "Apple",
            .arm => "ARM",
            .unknown => "Unknown",
        };
    }
};

/// SIMD instruction set levels
pub const SimdLevel = enum {
    none,       // No SIMD support
    sse2,       // x86 SSE2
    sse4_1,     // x86 SSE4.1
    avx,        // x86 AVX
    avx2,       // x86 AVX2
    avx512,     // x86 AVX-512
    neon,       // ARM NEON
    sve,        // ARM SVE
    sve2,       // ARM SVE2
    
    pub fn getVectorSize(self: SimdLevel) usize {
        return switch (self) {
            .none => 1,
            .sse2, .sse4_1 => 16,
            .avx, .avx2 => 32,
            .avx512 => 64,
            .neon => 16,
            .sve, .sve2 => 16, // Variable, but 16 is minimum
        };
    }
    
    pub fn getName(self: SimdLevel) []const u8 {
        return switch (self) {
            .none => "Scalar",
            .sse2 => "SSE2",
            .sse4_1 => "SSE4.1",
            .avx => "AVX",
            .avx2 => "AVX2",
            .avx512 => "AVX-512",
            .neon => "NEON",
            .sve => "SVE",
            .sve2 => "SVE2",
        };
    }
};

/// CPU features structure
pub const CpuFeatures = struct {
    // Vendor
    vendor: CpuVendor = .unknown,
    
    // x86 features
    sse: bool = false,
    sse2: bool = false,
    sse3: bool = false,
    ssse3: bool = false,
    sse4_1: bool = false,
    sse4_2: bool = false,
    avx: bool = false,
    avx2: bool = false,
    avx512f: bool = false,
    avx512bw: bool = false,
    avx512vl: bool = false,
    avx512dq: bool = false,
    avx512cd: bool = false,
    avx512er: bool = false,
    avx512pf: bool = false,
    avx512vbmi: bool = false,
    avx512vbmi2: bool = false,
    avx_vnni: bool = false,
    
    // ARM features
    neon: bool = false,
    sve: bool = false,
    sve2: bool = false,
    
    // Other features
    fma: bool = false,
    bmi1: bool = false,
    bmi2: bool = false,
    popcnt: bool = false,
    lzcnt: bool = false,
    movbe: bool = false,
    
    // Cache information
    cache_line_size: usize = 64,
    l1_data_cache: usize = 32 * 1024,
    l1_inst_cache: usize = 32 * 1024,
    l2_cache: usize = 256 * 1024,
    l3_cache: usize = 0,
    
    /// Get the best available SIMD level
    pub fn getBestSimdLevel(self: CpuFeatures) SimdLevel {
        if (builtin.cpu.arch.isX86()) {
            if (self.avx512f and self.avx512bw and self.avx512vl) {
                return .avx512;
            } else if (self.avx2) {
                return .avx2;
            } else if (self.avx) {
                return .avx;
            } else if (self.sse4_1) {
                return .sse4_1;
            } else if (self.sse2) {
                return .sse2;
            }
        } else if (builtin.cpu.arch.isAARCH64()) {
            if (self.sve2) {
                return .sve2;
            } else if (self.sve) {
                return .sve;
            } else if (self.neon) {
                return .neon;
            }
        }
        return .none;
    }
    
    /// Check if a specific SIMD level is supported
    pub fn supportsSimdLevel(self: CpuFeatures, level: SimdLevel) bool {
        return switch (level) {
            .none => true,
            .sse2 => self.sse2,
            .sse4_1 => self.sse4_1,
            .avx => self.avx,
            .avx2 => self.avx2,
            .avx512 => self.avx512f and self.avx512bw and self.avx512vl,
            .neon => self.neon,
            .sve => self.sve,
            .sve2 => self.sve2,
        };
    }
};

/// Global CPU features instance (cached)
var cached_features: ?CpuFeatures = null;
var features_mutex = std.Thread.Mutex{};

/// Detect CPU features (cached)
pub fn detect() CpuFeatures {
    features_mutex.lock();
    defer features_mutex.unlock();
    
    if (cached_features) |features| {
        return features;
    }
    
    const features = detectUncached();
    cached_features = features;
    return features;
}

/// Detect CPU features (uncached)
pub fn detectUncached() CpuFeatures {
    var features = CpuFeatures{};
    
    if (builtin.cpu.arch.isX86()) {
        detectX86Features(&features);
    } else if (builtin.cpu.arch.isAARCH64()) {
        detectArmFeatures(&features);
    }
    
    // Detect cache sizes
    detectCacheSizes(&features);
    
    return features;
}

/// Detect x86 CPU features
fn detectX86Features(features: *CpuFeatures) void {
    if (!builtin.cpu.arch.isX86()) return;
    
    // Use builtin CPU features when available
    const cpu = builtin.cpu;
    
    // Check vendor
    features.vendor = detectX86Vendor();
    
    // Check features from builtin
    inline for (@typeInfo(@TypeOf(cpu.features)).Struct.fields) |field| {
        const feature_name = field.name;
        const feature_value = @field(cpu.features, feature_name);
        
        // Map CPU features to our structure
        if (std.mem.eql(u8, feature_name, "sse")) features.sse = feature_value;
        if (std.mem.eql(u8, feature_name, "sse2")) features.sse2 = feature_value;
        if (std.mem.eql(u8, feature_name, "sse3")) features.sse3 = feature_value;
        if (std.mem.eql(u8, feature_name, "ssse3")) features.ssse3 = feature_value;
        if (std.mem.eql(u8, feature_name, "sse4_1")) features.sse4_1 = feature_value;
        if (std.mem.eql(u8, feature_name, "sse4_2")) features.sse4_2 = feature_value;
        if (std.mem.eql(u8, feature_name, "avx")) features.avx = feature_value;
        if (std.mem.eql(u8, feature_name, "avx2")) features.avx2 = feature_value;
        if (std.mem.eql(u8, feature_name, "avx512f")) features.avx512f = feature_value;
        if (std.mem.eql(u8, feature_name, "avx512bw")) features.avx512bw = feature_value;
        if (std.mem.eql(u8, feature_name, "avx512vl")) features.avx512vl = feature_value;
        if (std.mem.eql(u8, feature_name, "fma")) features.fma = feature_value;
        if (std.mem.eql(u8, feature_name, "bmi")) features.bmi1 = feature_value;
        if (std.mem.eql(u8, feature_name, "bmi2")) features.bmi2 = feature_value;
        if (std.mem.eql(u8, feature_name, "popcnt")) features.popcnt = feature_value;
        if (std.mem.eql(u8, feature_name, "lzcnt")) features.lzcnt = feature_value;
        if (std.mem.eql(u8, feature_name, "movbe")) features.movbe = feature_value;
    }
}

/// Detect ARM CPU features
fn detectArmFeatures(features: *CpuFeatures) void {
    if (!builtin.cpu.arch.isAARCH64()) return;
    
    features.vendor = if (builtin.os.tag == .macos) .apple else .arm;
    
    // Check for NEON (standard on AArch64)
    features.neon = true;
    
    // Check for SVE/SVE2 through builtin features
    const cpu = builtin.cpu;
    inline for (@typeInfo(@TypeOf(cpu.features)).Struct.fields) |field| {
        const feature_name = field.name;
        const feature_value = @field(cpu.features, feature_name);
        
        if (std.mem.eql(u8, feature_name, "sve")) features.sve = feature_value;
        if (std.mem.eql(u8, feature_name, "sve2")) features.sve2 = feature_value;
    }
}

/// Detect x86 CPU vendor
fn detectX86Vendor() CpuVendor {
    if (comptime !builtin.cpu.arch.isX86()) return .unknown;
    
    // Check CPU model name if available
    const model = builtin.cpu.model.name;
    
    if (std.mem.indexOf(u8, model, "Intel") != null) {
        return .intel;
    } else if (std.mem.indexOf(u8, model, "AMD") != null) {
        return .amd;
    }
    
    return .unknown;
}

/// Detect cache sizes
fn detectCacheSizes(features: *CpuFeatures) void {
    // Use sensible defaults based on architecture
    if (builtin.cpu.arch.isX86()) {
        features.cache_line_size = 64;
        features.l1_data_cache = 32 * 1024;
        features.l1_inst_cache = 32 * 1024;
        features.l2_cache = 256 * 1024;
        features.l3_cache = 8 * 1024 * 1024; // 8MB typical for modern CPUs
    } else if (builtin.cpu.arch.isAARCH64()) {
        features.cache_line_size = 64;
        features.l1_data_cache = 64 * 1024;
        features.l1_inst_cache = 64 * 1024;
        features.l2_cache = 1024 * 1024;
        
        if (features.vendor == .apple) {
            // Apple Silicon has larger caches
            features.l1_data_cache = 128 * 1024;
            features.l1_inst_cache = 192 * 1024;
            features.l2_cache = 4 * 1024 * 1024;
        }
    }
}

/// Get a string representation of CPU features
pub fn getFeatureString(features: CpuFeatures) []const u8 {
    const level = features.getBestSimdLevel();
    return level.getName();
}

/// Check if running on Apple Silicon
pub fn isAppleSilicon() bool {
    return builtin.os.tag == .macos and builtin.cpu.arch.isAARCH64();
}

/// Get optimal chunk size based on CPU features
pub fn getOptimalChunkSize(features: CpuFeatures) usize {
    // Base chunk size on L2 cache size
    const l2_size = features.l2_cache;
    
    // Use 1/4 of L2 cache as chunk size
    var chunk_size = l2_size / 4;
    
    // Align to vector size
    const vector_size = features.getBestSimdLevel().getVectorSize();
    chunk_size = (chunk_size / vector_size) * vector_size;
    
    // Clamp to reasonable range
    chunk_size = @max(chunk_size, 16 * 1024);  // Min 16KB
    chunk_size = @min(chunk_size, 256 * 1024); // Max 256KB
    
    return chunk_size;
}

// Tests
test "CPU feature detection" {
    const features = detect();
    
    // Should have some basic features
    if (builtin.cpu.arch.isX86()) {
        // x86_64 always has SSE2
        try std.testing.expect(features.sse2);
    } else if (builtin.cpu.arch.isAARCH64()) {
        // AArch64 always has NEON
        try std.testing.expect(features.neon);
    }
    
    // Best SIMD level should not be none on modern CPUs
    const best_level = features.getBestSimdLevel();
    try std.testing.expect(best_level != .none);
}

test "Optimal chunk size" {
    const features = detect();
    const chunk_size = getOptimalChunkSize(features);
    
    // Should be within reasonable range
    try std.testing.expect(chunk_size >= 16 * 1024);
    try std.testing.expect(chunk_size <= 256 * 1024);
    
    // Should be aligned to vector size
    const vector_size = features.getBestSimdLevel().getVectorSize();
    try std.testing.expect(chunk_size % vector_size == 0);
}