const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <benchmark_output_file>\n", .{args[0]});
        std.process.exit(1);
    }

    const filename = args[1];
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    var performance_data = PerformanceData.init();
    try parseBenchmarkOutput(content, &performance_data);

    // Output in JSON format for CI/CD parsing
    try outputJson(&performance_data);
}

const PerformanceData = struct {
    throughput_gbps: f64 = 0.0,
    memory_mb: f64 = 0.0,
    simd_efficiency: f64 = 0.0,
    cache_hit_ratio: f64 = 0.0,
    thread_count: u32 = 0,
    cpu_features: std.ArrayList(u8),
    test_duration_ms: u64 = 0,
    input_size_mb: f64 = 0.0,

    pub fn init() PerformanceData {
        return .{
            .cpu_features = std.ArrayList(u8).init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *PerformanceData) void {
        self.cpu_features.deinit();
    }
};

fn parseBenchmarkOutput(content: []const u8, data: *PerformanceData) !void {
    var lines = std.mem.splitSequence(u8, content, "\n");

    while (lines.next()) |line| {
        // Parse throughput (GB/s)
        if (std.mem.indexOf(u8, line, "GB/s") != null) {
            if (extractFloat(line, "GB/s")) |throughput| {
                data.throughput_gbps = throughput;
            }
        }

        // Parse memory usage (MB)
        if (std.mem.indexOf(u8, line, "Memory:") != null) {
            if (extractFloat(line, "MB")) |memory| {
                data.memory_mb = memory;
            }
        }

        // Parse SIMD efficiency (%)
        if (std.mem.indexOf(u8, line, "SIMD Efficiency:") != null) {
            if (extractFloat(line, "%")) |efficiency| {
                data.simd_efficiency = efficiency;
            }
        }

        // Parse cache hit ratio (%)
        if (std.mem.indexOf(u8, line, "Cache Hit Ratio:") != null) {
            if (extractFloat(line, "%")) |ratio| {
                data.cache_hit_ratio = ratio;
            }
        }

        // Parse thread count
        if (std.mem.indexOf(u8, line, "Threads:") != null) {
            if (extractU32(line)) |threads| {
                data.thread_count = threads;
            }
        }

        // Parse CPU features
        if (std.mem.indexOf(u8, line, "CPU Features:") != null) {
            if (extractCpuFeatures(line)) |features| {
                try data.cpu_features.appendSlice(features);
            }
        }

        // Parse test duration
        if (std.mem.indexOf(u8, line, "Duration:") != null) {
            if (extractDuration(line)) |duration| {
                data.test_duration_ms = duration;
            }
        }

        // Parse input size
        if (std.mem.indexOf(u8, line, "Input Size:") != null) {
            if (extractFloat(line, "MB")) |size| {
                data.input_size_mb = size;
            }
        }
    }
}

fn extractFloat(line: []const u8, unit: []const u8) ?f64 {
    const unit_pos = std.mem.indexOf(u8, line, unit) orelse return null;
    const before_unit = line[0..unit_pos];

    // Find the last number before the unit
    var i: usize = before_unit.len;
    while (i > 0) : (i -= 1) {
        const c = before_unit[i - 1];
        if (std.ascii.isDigit(c) or c == '.') {
            continue;
        }
        break;
    }

    if (i >= before_unit.len) return null;

    const number_str = std.mem.trim(u8, before_unit[i..], " \t");
    return std.fmt.parseFloat(f64, number_str) catch null;
}

fn extractU32(line: []const u8) ?u32 {
    var iter = std.mem.tokenizeAny(u8, line, " \t");
    while (iter.next()) |token| {
        if (std.fmt.parseInt(u32, token, 10)) |value| {
            return value;
        } else |_| {
            continue;
        }
    }
    return null;
}

fn extractCpuFeatures(line: []const u8) ?[]const u8 {
    const prefix = "CPU Features:";
    const prefix_pos = std.mem.indexOf(u8, line, prefix) orelse return null;
    const features = std.mem.trim(u8, line[prefix_pos + prefix.len ..], " \t");
    return if (features.len > 0) features else null;
}

fn extractDuration(line: []const u8) ?u64 {
    const prefix = "Duration:";
    const prefix_pos = std.mem.indexOf(u8, line, prefix) orelse return null;
    const duration_str = std.mem.trim(u8, line[prefix_pos + prefix.len ..], " \t");

    // Parse duration in format like "1234.56ms" or "1.23s"
    if (std.mem.endsWith(u8, duration_str, "ms")) {
        const ms_str = duration_str[0 .. duration_str.len - 2];
        const ms = std.fmt.parseFloat(f64, ms_str) catch return null;
        return @as(u64, @intFromFloat(ms));
    } else if (std.mem.endsWith(u8, duration_str, "s")) {
        const s_str = duration_str[0 .. duration_str.len - 1];
        const seconds = std.fmt.parseFloat(f64, s_str) catch null;
        return if (seconds) |s| @as(u64, @intFromFloat(s * 1000.0)) else null;
    }

    return null;
}

fn outputJson(data: *PerformanceData) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print(
        \\{{
        \\  "performance": {{
        \\    "throughput_gbps": {d:.2},
        \\    "memory_mb": {d:.2},
        \\    "simd_efficiency": {d:.1},
        \\    "cache_hit_ratio": {d:.1},
        \\    "thread_count": {d},
        \\    "cpu_features": "{s}",
        \\    "test_duration_ms": {d},
        \\    "input_size_mb": {d:.2}
        \\  }},
        \\  "badges": {{
        \\    "performance": "https://img.shields.io/badge/Performance-{d:.2}%20GB%2Fs-brightgreen?style=for-the-badge&logo=zig",
        \\    "memory": "https://img.shields.io/badge/Memory-O(1)-blue?style=for-the-badge&logo=memory",
        \\    "simd": "https://img.shields.io/badge/SIMD-{d:.1}%25-orange?style=for-the-badge&logo=cpu",
        \\    "build": "https://img.shields.io/badge/Build-Passing-brightgreen?style=for-the-badge&logo=github-actions",
        \\    "zig": "https://img.shields.io/badge/Zig-0.12.0-purple?style=for-the-badge&logo=zig"
        \\  }}
        \\}}
        \\
    , .{
        data.throughput_gbps,
        data.memory_mb,
        data.simd_efficiency,
        data.cache_hit_ratio,
        data.thread_count,
        data.cpu_features.items,
        data.test_duration_ms,
        data.input_size_mb,
        data.throughput_gbps,
        data.simd_efficiency,
    });
}
