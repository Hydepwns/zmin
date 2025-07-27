const std = @import("std");

pub const CpuInfo = struct {
    vendor: CpuVendor,
    model: []const u8,
    features: CpuFeatures,
    cache_info: CacheInfo,

    pub fn init() CpuInfo {
        const vendor = detectCpuVendor();
        const features = detectCpuFeatures();
        const cache_info = detectCacheInfo();

        return CpuInfo{
            .vendor = vendor,
            .model = detectCpuModel(),
            .features = features,
            .cache_info = cache_info,
        };
    }

    pub fn format(self: CpuInfo, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("CPU: {s} ({s}) - {any}", .{
            self.model,
            @tagName(self.vendor),
            self.features,
        });
    }
};

pub const CpuVendor = enum {
    intel,
    amd,
    unknown,
};

pub const CpuFeatures = struct {
    // SIMD extensions
    sse: bool,
    sse2: bool,
    sse3: bool,
    ssse3: bool,
    sse4_1: bool,
    sse4_2: bool,
    avx: bool,
    avx2: bool,
    avx512f: bool,
    avx512dq: bool,
    avx512bw: bool,
    avx512vl: bool,

    // Other features
    popcnt: bool,
    bmi1: bool,
    bmi2: bool,

    pub fn format(self: CpuFeatures, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Features: SSE2: {}, AVX: {}, AVX2: {}, AVX-512: {}", .{
            self.sse2,
            self.avx,
            self.avx2,
            self.avx512f,
        });
    }

    pub fn hasAvx512(self: CpuFeatures) bool {
        return self.avx512f and self.avx512dq and self.avx512bw and self.avx512vl;
    }

    pub fn hasAvx2(self: CpuFeatures) bool {
        return self.avx2;
    }

    pub fn hasSse2(self: CpuFeatures) bool {
        return self.sse2;
    }
};

pub const CacheInfo = struct {
    l1_data_size: u32,
    l1_instruction_size: u32,
    l2_size: u32,
    l3_size: u32,

    pub fn format(self: CacheInfo, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Cache: L1d: {}KB, L1i: {}KB, L2: {}KB, L3: {}KB", .{
            self.l1_data_size / 1024,
            self.l1_instruction_size / 1024,
            self.l2_size / 1024,
            self.l3_size / 1024,
        });
    }
};

fn detectCpuVendor() CpuVendor {
    // Read CPU vendor string using CPUID
    const vendor_string = getCpuVendorString();

    if (std.mem.startsWith(u8, &vendor_string, "GenuineIntel")) {
        return .intel;
    } else if (std.mem.startsWith(u8, &vendor_string, "AuthenticAMD")) {
        return .amd;
    } else {
        return .unknown;
    }
}

fn getCpuVendorString() [12]u8 {
    // CPUID with EAX=0 returns vendor string in EBX+EDX+ECX
    var vendor: [12]u8 = undefined;

    // This is a simplified implementation
    // In a real implementation, we would use inline assembly or Zig's CPUID support
    vendor = "UnknownCPU  ".*;

    return vendor;
}

fn detectCpuModel() []const u8 {
    // In a real implementation, this would read from /proc/cpuinfo on Linux
    // or use CPUID to get processor information
    return "Unknown Model";
}

fn detectCpuFeatures() CpuFeatures {
    const builtin = @import("builtin");
    const cpu = builtin.cpu;

    if (cpu.arch != .x86_64) {
        return CpuFeatures{
            .sse = false,
            .sse2 = false,
            .sse3 = false,
            .ssse3 = false,
            .sse4_1 = false,
            .sse4_2 = false,
            .avx = false,
            .avx2 = false,
            .avx512f = false,
            .avx512dq = false,
            .avx512bw = false,
            .avx512vl = false,
            .popcnt = false,
            .bmi1 = false,
            .bmi2 = false,
        };
    }

    // Use Zig's built-in CPU feature detection
    return CpuFeatures{
        .sse = std.Target.x86.featureSetHas(cpu.features, .sse),
        .sse2 = std.Target.x86.featureSetHas(cpu.features, .sse2),
        .sse3 = std.Target.x86.featureSetHas(cpu.features, .sse3),
        .ssse3 = std.Target.x86.featureSetHas(cpu.features, .ssse3),
        .sse4_1 = std.Target.x86.featureSetHas(cpu.features, .sse4_1),
        .sse4_2 = std.Target.x86.featureSetHas(cpu.features, .sse4_2),
        .avx = std.Target.x86.featureSetHas(cpu.features, .avx),
        .avx2 = std.Target.x86.featureSetHas(cpu.features, .avx2),
        .avx512f = std.Target.x86.featureSetHas(cpu.features, .avx512f),
        .avx512dq = std.Target.x86.featureSetHas(cpu.features, .avx512dq),
        .avx512bw = std.Target.x86.featureSetHas(cpu.features, .avx512bw),
        .avx512vl = std.Target.x86.featureSetHas(cpu.features, .avx512vl),
        .popcnt = std.Target.x86.featureSetHas(cpu.features, .popcnt),
        .bmi1 = std.Target.x86.featureSetHas(cpu.features, .bmi),
        .bmi2 = std.Target.x86.featureSetHas(cpu.features, .bmi2),
    };
}

fn detectCacheInfo() CacheInfo {
    // In a real implementation, this would use CPUID to get cache information
    // For now, return reasonable defaults
    return CacheInfo{
        .l1_data_size = 32 * 1024, // 32KB typical
        .l1_instruction_size = 32 * 1024, // 32KB typical
        .l2_size = 256 * 1024, // 256KB typical
        .l3_size = 8 * 1024 * 1024, // 8MB typical
    };
}

pub fn getOptimalSimdStrategy() SimdStrategy {
    const cpu_info = CpuInfo.init();

    if (cpu_info.features.hasAvx512()) {
        return .avx512;
    } else if (cpu_info.features.hasAvx2()) {
        return .avx2;
    } else if (cpu_info.features.hasSse2()) {
        return .sse2;
    } else {
        return .scalar;
    }
}

pub const SimdStrategy = enum {
    avx512,
    avx2,
    sse2,
    scalar,

    pub fn format(self: SimdStrategy, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}", .{@tagName(self)});
    }

    pub fn getSimdWidth(self: SimdStrategy) usize {
        return switch (self) {
            .avx512 => 64,
            .avx2 => 32,
            .sse2 => 16,
            .scalar => 1,
        };
    }
};
