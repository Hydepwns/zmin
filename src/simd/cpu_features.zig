// CPU feature detection for SIMD optimizations
const std = @import("std");
const builtin = @import("builtin");

pub const CPUFeatures = struct {
    sse2: bool = false,
    sse4_1: bool = false,
    avx: bool = false,
    avx2: bool = false,
    avx512f: bool = false, // AVX-512 Foundation
    avx512bw: bool = false, // AVX-512 Byte and Word
    avx512vl: bool = false, // AVX-512 Vector Length
    avx_vnni: bool = false, // AVX Vector Neural Network Instructions
    bmi1: bool = false, // Bit Manipulation Instructions 1
    bmi2: bool = false, // Bit Manipulation Instructions 2
    popcnt: bool = false, // Population Count

    pub fn detect() CPUFeatures {
        var features = CPUFeatures{};

        if (builtin.target.cpu.arch == .x86_64) {
            features = detectX86Features();
        }

        return features;
    }

    pub fn getBestSIMDLevel(self: CPUFeatures) SIMDLevel {
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
        } else {
            return .scalar;
        }
    }

    pub const SIMDLevel = enum {
        scalar,
        sse2,
        sse4_1,
        avx,
        avx2,
        avx512,

        pub fn getVectorSize(self: SIMDLevel) usize {
            return switch (self) {
                .scalar => 1,
                .sse2, .sse4_1 => 16, // 128-bit
                .avx, .avx2 => 32, // 256-bit
                .avx512 => 64, // 512-bit
            };
        }

        pub fn getName(self: SIMDLevel) []const u8 {
            return switch (self) {
                .scalar => "Scalar",
                .sse2 => "SSE2",
                .sse4_1 => "SSE4.1",
                .avx => "AVX",
                .avx2 => "AVX2",
                .avx512 => "AVX-512",
            };
        }
    };
};

// X86-64 specific feature detection
fn detectX86Features() CPUFeatures {
    var features = CPUFeatures{};

    // Use CPUID instruction to detect features
    const cpuid_result = cpuid(1, 0);
    const ecx = cpuid_result[2];
    const edx = cpuid_result[3];

    // Basic features from CPUID(1)
    features.sse2 = (edx & (1 << 26)) != 0;
    features.sse4_1 = (ecx & (1 << 19)) != 0;
    features.avx = (ecx & (1 << 28)) != 0;
    features.popcnt = (ecx & (1 << 23)) != 0;

    // Extended features from CPUID(7)
    const cpuid7_result = cpuid(7, 0);
    const ebx7 = cpuid7_result[1];
    const ecx7 = cpuid7_result[2];

    features.avx2 = (ebx7 & (1 << 5)) != 0;
    features.bmi1 = (ebx7 & (1 << 3)) != 0;
    features.bmi2 = (ebx7 & (1 << 8)) != 0;
    features.avx512f = (ebx7 & (1 << 16)) != 0;
    features.avx512bw = (ebx7 & (1 << 30)) != 0;
    features.avx512vl = (ebx7 & (1 << 31)) != 0;
    features.avx_vnni = (ecx7 & (1 << 4)) != 0;

    return features;
}

// CPUID instruction wrapper
fn cpuid(leaf: u32, subleaf: u32) [4]u32 {
    if (builtin.target.cpu.arch != .x86_64) {
        return [4]u32{ 0, 0, 0, 0 };
    }

    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;

    // Inline assembly for CPUID
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [leaf] "{eax}" (leaf),
          [subleaf] "{ecx}" (subleaf),
    );

    return [4]u32{ eax, ebx, ecx, edx };
}

// Alternative feature detection using /proc/cpuinfo on Linux
fn detectFromProcCpuinfo(allocator: std.mem.Allocator) !CPUFeatures {
    var features = CPUFeatures{};

    if (builtin.os.tag != .linux) return features;

    const file = std.fs.openFileAbsolute("/proc/cpuinfo", .{}) catch return features;
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 16384);
    defer allocator.free(content);

    // Parse flags line
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "flags")) {
            const flags_start = std.mem.indexOf(u8, line, ":") orelse continue;
            const flags = line[flags_start + 1 ..];

            features.sse2 = std.mem.indexOf(u8, flags, "sse2") != null;
            features.sse4_1 = std.mem.indexOf(u8, flags, "sse4_1") != null;
            features.avx = std.mem.indexOf(u8, flags, "avx") != null;
            features.avx2 = std.mem.indexOf(u8, flags, "avx2") != null;
            features.avx512f = std.mem.indexOf(u8, flags, "avx512f") != null;
            features.avx512bw = std.mem.indexOf(u8, flags, "avx512bw") != null;
            features.avx512vl = std.mem.indexOf(u8, flags, "avx512vl") != null;
            features.avx_vnni = std.mem.indexOf(u8, flags, "avx_vnni") != null;
            features.bmi1 = std.mem.indexOf(u8, flags, "bmi1") != null;
            features.bmi2 = std.mem.indexOf(u8, flags, "bmi2") != null;
            features.popcnt = std.mem.indexOf(u8, flags, "popcnt") != null;

            break;
        }
    }

    return features;
}
