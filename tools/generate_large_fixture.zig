const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const file = try std.fs.cwd().createFile("tests/fixtures/large.json", .{});
    defer file.close();

    var writer = file.writer();
    
    try writer.writeAll("{\n  \"data\": [\n");
    
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        if (i > 0) try writer.writeAll(",\n");
        try writer.print("    {{\n      \"id\": {},\n      \"name\": \"Item {}\",\n      \"value\": {},\n      \"active\": {},\n      \"tags\": [\"tag1\", \"tag2\", \"tag3\"]\n    }}", .{ 
            i, i, @as(f64, @floatFromInt(i)) * 1.5, i % 2 == 0 
        });
    }
    
    try writer.writeAll("\n  ],\n");
    try writer.writeAll("  \"metadata\": {\n");
    try writer.writeAll("    \"total_count\": 1000,\n");
    try writer.writeAll("    \"generated_at\": \"2023-01-01T00:00:00Z\",\n");
    try writer.writeAll("    \"version\": \"1.0\"\n");
    try writer.writeAll("  }\n");
    try writer.writeAll("}\n");
    
    std.debug.print("Generated large.json with 1000 items\n", .{});
}