//! Common system utilities for all minifier implementations
//! This module consolidates duplicated system-level functionality

const std = @import("std");
const builtin = @import("builtin");

/// Get current memory usage of the process in bytes
pub fn getCurrentMemoryUsage() u64 {
    return switch (builtin.os.tag) {
        .linux => getLinuxMemoryUsage(),
        .macos => getMacOSMemoryUsage(),
        .windows => getWindowsMemoryUsage(),
        else => estimateProcessMemoryUsage(),
    };
}

/// Get memory usage on Linux using /proc/self/status
fn getLinuxMemoryUsage() u64 {
    const file = std.fs.openFileAbsolute("/proc/self/status", .{}) catch return estimateProcessMemoryUsage();
    defer file.close();

    var buf: [4096]u8 = undefined;
    const bytes_read = file.read(&buf) catch return estimateProcessMemoryUsage();
    const content = buf[0..bytes_read];

    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "VmRSS:")) {
            const value_start = std.mem.indexOf(u8, line, ":") orelse continue;
            const value_str = std.mem.trim(u8, line[value_start + 1 ..], " \t");
            const kb_start = std.mem.indexOf(u8, value_str, " ") orelse continue;
            const kb_str = value_str[0..kb_start];
            const kb = std.fmt.parseInt(u64, kb_str, 10) catch return estimateProcessMemoryUsage();
            return kb * 1024; // Convert KB to bytes
        }
    }
    return estimateProcessMemoryUsage();
}

/// Get memory usage on macOS using mach APIs
fn getMacOSMemoryUsage() u64 {
    // TODO: Implement proper macOS memory usage detection
    return estimateProcessMemoryUsage();
}

/// Get memory usage on Windows using Windows APIs
fn getWindowsMemoryUsage() u64 {
    // TODO: Implement proper Windows memory usage detection
    return estimateProcessMemoryUsage();
}

/// Fallback memory estimation based on allocator statistics
fn estimateProcessMemoryUsage() u64 {
    // Conservative estimate: 10MB base + some runtime overhead
    return 10 * 1024 * 1024;
}

/// Get total system memory
pub fn getTotalMemory() u64 {
    return switch (builtin.os.tag) {
        .linux => getLinuxTotalMemory(),
        .macos => getMacOSTotalMemory(),
        .windows => getWindowsTotalMemory(),
        else => 4 * 1024 * 1024 * 1024, // Default to 4GB
    };
}

fn getLinuxTotalMemory() u64 {
    const file = std.fs.openFileAbsolute("/proc/meminfo", .{}) catch return 4 * 1024 * 1024 * 1024;
    defer file.close();

    var buf: [4096]u8 = undefined;
    const bytes_read = file.read(&buf) catch return 4 * 1024 * 1024 * 1024;
    const content = buf[0..bytes_read];

    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            const value_start = std.mem.indexOf(u8, line, ":") orelse continue;
            const value_str = std.mem.trim(u8, line[value_start + 1 ..], " \t");
            const kb_start = std.mem.indexOf(u8, value_str, " ") orelse continue;
            const kb_str = value_str[0..kb_start];
            const kb = std.fmt.parseInt(u64, kb_str, 10) catch return 4 * 1024 * 1024 * 1024;
            return kb * 1024; // Convert KB to bytes
        }
    }
    return 4 * 1024 * 1024 * 1024;
}

fn getMacOSTotalMemory() u64 {
    // TODO: Implement proper macOS total memory detection
    return 8 * 1024 * 1024 * 1024; // Default to 8GB for macOS
}

fn getWindowsTotalMemory() u64 {
    // TODO: Implement proper Windows total memory detection
    return 8 * 1024 * 1024 * 1024; // Default to 8GB for Windows
}

/// Get number of CPU cores
pub fn getCpuCount() u32 {
    return switch (builtin.os.tag) {
        .linux => getLinuxCpuCount(),
        .macos => getMacOSCpuCount(),
        .windows => getWindowsCpuCount(),
        else => 4, // Default to 4 cores
    };
}

fn getLinuxCpuCount() u32 {
    const file = std.fs.openFileAbsolute("/proc/cpuinfo", .{}) catch return 4;
    defer file.close();

    var buf: [16384]u8 = undefined;
    const bytes_read = file.read(&buf) catch return 4;
    const content = buf[0..bytes_read];

    var count: u32 = 0;
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "processor")) {
            count += 1;
        }
    }
    return if (count > 0) count else 4;
}

fn getMacOSCpuCount() u32 {
    // TODO: Implement proper macOS CPU detection
    return 8; // Default to 8 cores for macOS
}

fn getWindowsCpuCount() u32 {
    // TODO: Implement proper Windows CPU detection
    return 4; // Default to 4 cores for Windows
}
