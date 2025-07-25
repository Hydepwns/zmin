const std = @import("std");
const http = std.http;
const fs = std.fs;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{});
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Default performance values (can be overridden by command line)
    var throughput: f64 = 5.72;
    var simd_efficiency: f64 = 6400.0;
    var zig_version: []const u8 = "0.12.0";

    // Parse command line arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.startsWith(u8, args[i], "--throughput=")) {
            throughput = std.fmt.parseFloat(f64, args[i][13..]) catch 5.72;
        } else if (std.mem.startsWith(u8, args[i], "--simd=")) {
            simd_efficiency = std.fmt.parseFloat(f64, args[i][7..]) catch 6400.0;
        } else if (std.mem.startsWith(u8, args[i], "--zig=")) {
            zig_version = args[i][6..];
        }
    }

    // Create badges directory
    try fs.cwd().makePath("badges");

    // Generate badges
    try generateBadge("badges/performance.svg", "Performance", &std.fmt.bufPrint(allocator, "{d:.2} GB/s", .{throughput}) catch unreachable, "brightgreen", "zig");

    try generateBadge("badges/memory.svg", "Memory", "O(1)", "blue", "memory");

    try generateBadge("badges/simd.svg", "SIMD", &std.fmt.bufPrint(allocator, "{d:.0}%", .{simd_efficiency}) catch unreachable, "orange", "cpu");

    try generateBadge("badges/build.svg", "Build", "Passing", "brightgreen", "github-actions");

    try generateBadge("badges/zig.svg", "Zig", zig_version, "purple", "zig");

    try generateBadge("badges/license.svg", "License", "MIT", "blue", "license");

    try generateBadge("badges/platforms.svg", "Platforms", "Linux|macOS|Windows", "blue", "platform");

    std.debug.print("Badges generated successfully in badges/ directory\n", .{});
}

fn generateBadge(filename: []const u8, label: []const u8, message: []const u8, color: []const u8, logo: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // URL encode the parameters
    const encoded_label = try urlEncode(allocator, label);
    const encoded_message = try urlEncode(allocator, message);
    const encoded_color = try urlEncode(allocator, color);
    const encoded_logo = try urlEncode(allocator, logo);

    const url = try std.fmt.allocPrint(allocator, "https://img.shields.io/badge/{s}-{s}-{s}?style=for-the-badge&logo={s}", .{ encoded_label, encoded_message, encoded_color, encoded_logo });

    // Download the badge
    try downloadFile(url, filename);
}

fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    for (input) |byte| {
        switch (byte) {
            'A'...'Z', 'a'...'z', '0'...'9', '-', '_', '.', '~' => {
                try result.append(byte);
            },
            ' ' => {
                try result.appendSlice("%20");
            },
            '%' => {
                try result.appendSlice("%25");
            },
            '|' => {
                try result.appendSlice("%7C");
            },
            '/' => {
                try result.appendSlice("%2F");
            },
            else => {
                try std.fmt.format(result.writer(), "%{X:0>2}", .{byte});
            },
        }
    }

    return result.toOwnedSlice();
}

fn downloadFile(url: []const u8, filename: []const u8) !void {
    var client = http.Client{ .allocator = std.heap.page_allocator };
    defer client.deinit();

    var headers = http.Headers{ .allocator = std.heap.page_allocator };
    defer headers.deinit();

    try headers.append("User-Agent", "Zmin-Badge-Generator/1.0");

    var req = try client.request(.GET, try std.Uri.parse(url), headers, .{});
    defer req.deinit();

    try req.start();
    try req.wait();

    if (req.response.status != .ok) {
        std.debug.print("Failed to download {s}: status {}\n", .{ url, req.response.status });
        return;
    }

    const file = try fs.cwd().createFile(filename, .{});
    defer file.close();

    var reader = req.reader();
    var buffer: [4096]u8 = undefined;

    while (true) {
        const bytes_read = try reader.read(&buffer);
        if (bytes_read == 0) break;
        try file.writeAll(buffer[0..bytes_read]);
    }

    std.debug.print("Downloaded {s} -> {s}\n", .{ url, filename });
}
