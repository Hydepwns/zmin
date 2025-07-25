//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

// Export the minifier module
pub const minifier = @import("minifier/mod.zig");

// Export other modules
pub const parallel = @import("parallel/mod.zig");
pub const parallel_minifier = parallel.ParallelMinifier;
pub const parallel_minifier_simple = parallel.SimpleParallelMinifier;

