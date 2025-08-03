const benchmark = @import("../src/v2/benchmark.zig");

pub fn main() !void {
    try benchmark.runBenchmark();
}