const std = @import("std");
const TurboMinifier = @import("../src/modes/turbo_minifier.zig").TurboMinifier;
const TurboMinifierOptimized = @import("../src/modes/turbo_minifier_optimized.zig").TurboMinifierOptimized;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_json =
        \\{  "name"  :  "John Doe"  ,  "age"  :  30  ,  "active"  :  true  }
    ;

    std.debug.print("Input: '{s}'\n", .{test_json});

    // Test original
    var original = TurboMinifier.init(allocator);
    const output1 = try allocator.alloc(u8, test_json.len);
    defer allocator.free(output1);
    const len1 = try original.minify(test_json, output1);
    std.debug.print("Original:  '{s}'\n", .{output1[0..len1]});

    // Test optimized
    var optimized = TurboMinifierOptimized.init(allocator);
    const output2 = try allocator.alloc(u8, test_json.len);
    defer allocator.free(output2);
    const len2 = try optimized.minify(test_json, output2);
    std.debug.print("Optimized: '{s}'\n", .{output2[0..len2]});

    // Compare byte by byte
    const min_len = @min(len1, len2);
    std.debug.print("Lengths: {} vs {}\n", .{ len1, len2 });
    for (0..min_len) |i| {
        if (output1[i] != output2[i]) {
            std.debug.print("Diff at {}: '{}' vs '{}'\n", .{ i, output1[i], output2[i] });
            break;
        }
    }
}
