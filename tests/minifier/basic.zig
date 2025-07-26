const std = @import("std");
const testing = std.testing;

// Import helper modules
const helpers = @import("test_helpers.zig");
const generators = @import("test_data_generators.zig");
const assertions = @import("assertion_helpers.zig");

test "minifier - basic functionality" {
    try helpers.testMinify("{\"test\":\"value\"}", "{\"test\":\"value\"}");
}

test "minifier - whitespace removal" {
    try helpers.testMinify("{\n  \"test\": \"value\",\n  \"number\": 42\n}", "{\"test\":\"value\",\"number\":42}");
}
