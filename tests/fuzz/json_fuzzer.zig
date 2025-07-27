//! JSON Fuzzing Tests
//!
//! This module implements fuzz testing to find edge cases and potential
//! crashes in the JSON minifier by generating random, malformed, and
//! adversarial inputs.

const std = @import("std");
const zmin = @import("zmin_lib");

/// Fuzzer configuration
pub const FuzzerConfig = struct {
    /// Maximum input size to generate
    max_input_size: usize = 10 * 1024, // 10KB
    /// Number of mutations per seed
    mutations_per_seed: u32 = 100,
    /// Timeout for each test (microseconds)
    timeout_us: u64 = 1_000_000, // 1 second
    /// Enable corpus collection
    collect_corpus: bool = true,
    /// Corpus directory
    corpus_dir: []const u8 = "tests/fuzz/corpus",
};

/// Mutation strategies for fuzzing
pub const MutationStrategy = enum {
    bit_flip, // Flip random bits
    byte_swap, // Swap random bytes
    byte_insert, // Insert random bytes
    byte_delete, // Delete random bytes
    byte_replace, // Replace random bytes
    structure_aware, // JSON-aware mutations
    boundary_values, // Insert boundary values
    nesting_attack, // Deep nesting attack

    pub fn getWeight(self: MutationStrategy) u32 {
        return switch (self) {
            .bit_flip => 10,
            .byte_swap => 10,
            .byte_insert => 15,
            .byte_delete => 15,
            .byte_replace => 20,
            .structure_aware => 20,
            .boundary_values => 5,
            .nesting_attack => 5,
        };
    }
};

/// Fuzzer for JSON minification
pub const JsonFuzzer = struct {
    allocator: std.mem.Allocator,
    config: FuzzerConfig,
    corpus: std.ArrayList([]u8),
    interesting_values: []const []const u8,
    crashes_found: u32 = 0,
    timeouts_found: u32 = 0,
    total_executions: u64 = 0,

    /// Interesting values to inject
    const interesting_json_values = [_][]const u8{
        // Edge case numbers
        "0", "-0", "1e308", "-1e308", "1e-308",
        "9223372036854775807", // i64 max
        "-9223372036854775808", // i64 min
        "1.7976931348623157e+308", // f64 max
        "2.2250738585072014e-308", // f64 min

        // Special strings
        "\"\"",
        "\" \"",
        "\"\\\"\"",
        "\"\\\\\"",
        "\"\\n\"",
        "\"\\u0000\"",
        "\"\\uD800\"", "\"\\uDFFF\"", // Invalid surrogates

        // Structural elements
        "{}",          "[]",
        "null",        "true",
        "false",       "{\"\":\"\"}",
        "[[[[[[[[[[[]]]]]]]]]]", // Deep nesting

        // Malformed JSON
        "{",
        "}",
        "[",
        "]",
        ",",
        ":",
        "\"",
        "{,}",
        "[,]",
        "{:}",
        "[:,]",
        "{'single': 'quotes'}", // Invalid quotes
        "{unquoted: key}", // Unquoted keys
        "[1, 2, 3,]", // Trailing comma
        "{\"a\": 1, \"a\": 2}", // Duplicate keys
    };

    pub fn init(allocator: std.mem.Allocator, config: FuzzerConfig) !JsonFuzzer {
        var corpus = std.ArrayList([]u8).init(allocator);

        // Load initial corpus
        if (config.collect_corpus) {
            try loadCorpus(allocator, &corpus, config.corpus_dir);
        }

        // Add seed inputs
        try corpus.append(try allocator.dupe(u8, "{}"));
        try corpus.append(try allocator.dupe(u8, "[]"));
        try corpus.append(try allocator.dupe(u8, "null"));

        return JsonFuzzer{
            .allocator = allocator,
            .config = config,
            .corpus = corpus,
            .interesting_values = &interesting_json_values,
        };
    }

    pub fn deinit(self: *JsonFuzzer) void {
        for (self.corpus.items) |item| {
            self.allocator.free(item);
        }
        self.corpus.deinit();
    }

    /// Run fuzzing campaign
    pub fn fuzz(self: *JsonFuzzer, duration_seconds: u64) !void {
        const start_time = std.time.timestamp();
        const end_time = start_time + duration_seconds;

        var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
        const random = prng.random();

        std.debug.print("Starting fuzzing campaign for {d} seconds...\n", .{duration_seconds});

        while (std.time.timestamp() < end_time) {
            // Select input from corpus
            const seed_input = if (self.corpus.items.len > 0)
                self.corpus.items[random.intRangeAtMost(usize, 0, self.corpus.items.len - 1)]
            else
                "";

            // Generate mutations
            for (0..self.config.mutations_per_seed) |_| {
                const mutated = try self.mutate(seed_input, random);
                defer self.allocator.free(mutated);

                // Test the mutated input
                const result = try self.testInput(mutated);

                if (result.interesting) {
                    // Add to corpus if interesting
                    try self.corpus.append(try self.allocator.dupe(u8, mutated));

                    if (self.config.collect_corpus) {
                        try self.saveToCorpus(mutated);
                    }
                }

                self.total_executions += 1;

                // Print progress
                if (self.total_executions % 10000 == 0) {
                    const elapsed = std.time.timestamp() - start_time;
                    const exec_per_sec = self.total_executions / @max(elapsed, 1);
                    std.debug.print("Executions: {d} | Crashes: {d} | Timeouts: {d} | Corpus: {d} | Speed: {d}/s\n", .{ self.total_executions, self.crashes_found, self.timeouts_found, self.corpus.items.len, exec_per_sec });
                }
            }
        }

        // Final report
        std.debug.print("\nFuzzing complete!\n", .{});
        std.debug.print("Total executions: {d}\n", .{self.total_executions});
        std.debug.print("Crashes found: {d}\n", .{self.crashes_found});
        std.debug.print("Timeouts found: {d}\n", .{self.timeouts_found});
        std.debug.print("Corpus size: {d}\n", .{self.corpus.items.len});
    }

    /// Test a single input
    fn testInput(self: *JsonFuzzer, input: []const u8) !FuzzResult {
        var result = FuzzResult{
            .crashed = false,
            .timeout = false,
            .interesting = false,
            .coverage_increase = false,
        };

        // Test with timeout protection
        const start = std.time.microTimestamp();

        // Try all modes
        for ([_]zmin.ProcessingMode{ .eco, .sport, .turbo }) |mode| {
            const output = zmin.minifyWithMode(self.allocator, input, mode) catch |err| {
                // Check if this is an expected error
                switch (err) {
                    error.InvalidJson,
                    error.UnexpectedEndOfInput,
                    error.InvalidCharacter,
                    error.InvalidEscapeSequence,
                    error.TrailingComma,
                    error.DuplicateKey,
                    => {
                        // Expected errors for invalid input
                        continue;
                    },
                    error.OutOfMemory => {
                        // Memory exhaustion could be interesting
                        result.interesting = true;
                        continue;
                    },
                    else => {
                        // Unexpected error - potential bug
                        std.debug.print("\nCRASH found with error: {}\n", .{err});
                        std.debug.print("Input: {s}\n", .{input});
                        std.debug.print("Mode: {s}\n", .{@tagName(mode)});
                        self.crashes_found += 1;
                        result.crashed = true;
                        result.interesting = true;
                        try self.saveCrash(input, err);
                        return result;
                    },
                }
            };

            // Free output if successful
            self.allocator.free(output);

            // Check timeout
            const elapsed = std.time.microTimestamp() - start;
            if (elapsed > self.config.timeout_us) {
                std.debug.print("\nTIMEOUT found (took {d}µs)\n", .{elapsed});
                std.debug.print("Input: {s}\n", .{input});
                self.timeouts_found += 1;
                result.timeout = true;
                result.interesting = true;
                return result;
            }
        }

        // Check if this input triggers new behavior
        // (In real implementation, would use coverage feedback)
        if (input.len > 1000 or std.mem.count(u8, input, "{") > 20) {
            result.coverage_increase = true;
            result.interesting = true;
        }

        return result;
    }

    /// Mutate input using various strategies
    fn mutate(self: *JsonFuzzer, input: []const u8, random: std.rand.Random) ![]u8 {
        // Select mutation strategy based on weights
        const strategy = selectMutationStrategy(random);

        return switch (strategy) {
            .bit_flip => try self.mutateBitFlip(input, random),
            .byte_swap => try self.mutateByteSwap(input, random),
            .byte_insert => try self.mutateByteInsert(input, random),
            .byte_delete => try self.mutateByteDelete(input, random),
            .byte_replace => try self.mutateByteReplace(input, random),
            .structure_aware => try self.mutateStructureAware(input, random),
            .boundary_values => try self.mutateBoundaryValues(input, random),
            .nesting_attack => try self.mutateNestingAttack(input, random),
        };
    }

    fn mutateBitFlip(self: *JsonFuzzer, input: []const u8, random: std.rand.Random) ![]u8 {
        if (input.len == 0) return try self.allocator.dupe(u8, input);

        var output = try self.allocator.dupe(u8, input);
        const byte_idx = random.intRangeAtMost(usize, 0, input.len - 1);
        const bit_idx = random.intRangeAtMost(u3, 0, 7);
        output[byte_idx] ^= @as(u8, 1) << bit_idx;

        return output;
    }

    fn mutateByteSwap(self: *JsonFuzzer, input: []const u8, random: std.rand.Random) ![]u8 {
        if (input.len < 2) return try self.allocator.dupe(u8, input);

        var output = try self.allocator.dupe(u8, input);
        const idx1 = random.intRangeAtMost(usize, 0, input.len - 1);
        const idx2 = random.intRangeAtMost(usize, 0, input.len - 1);

        const tmp = output[idx1];
        output[idx1] = output[idx2];
        output[idx2] = tmp;

        return output;
    }

    fn mutateByteInsert(self: *JsonFuzzer, input: []const u8, random: std.rand.Random) ![]u8 {
        const insert_pos = random.intRangeAtMost(usize, 0, input.len);
        const insert_byte = random.int(u8);

        var output = try self.allocator.alloc(u8, input.len + 1);
        @memcpy(output[0..insert_pos], input[0..insert_pos]);
        output[insert_pos] = insert_byte;
        @memcpy(output[insert_pos + 1 ..], input[insert_pos..]);

        return output;
    }

    fn mutateByteDelete(self: *JsonFuzzer, input: []const u8, random: std.rand.Random) ![]u8 {
        if (input.len == 0) return try self.allocator.dupe(u8, input);

        const delete_pos = random.intRangeAtMost(usize, 0, input.len - 1);

        var output = try self.allocator.alloc(u8, input.len - 1);
        @memcpy(output[0..delete_pos], input[0..delete_pos]);
        @memcpy(output[delete_pos..], input[delete_pos + 1 ..]);

        return output;
    }

    fn mutateByteReplace(self: *JsonFuzzer, input: []const u8, random: std.rand.Random) ![]u8 {
        if (input.len == 0) return try self.allocator.dupe(u8, input);

        var output = try self.allocator.dupe(u8, input);
        const replace_pos = random.intRangeAtMost(usize, 0, input.len - 1);
        output[replace_pos] = random.int(u8);

        return output;
    }

    fn mutateStructureAware(self: *JsonFuzzer, input: []const u8, random: std.rand.Random) ![]u8 {
        // Replace random part with interesting JSON value
        const interesting = self.interesting_values[random.intRangeAtMost(usize, 0, self.interesting_values.len - 1)];

        if (input.len == 0) return try self.allocator.dupe(u8, interesting);

        const replace_pos = random.intRangeAtMost(usize, 0, input.len - 1);
        const replace_len = random.intRangeAtMost(usize, 0, @min(10, input.len - replace_pos));

        var output = std.ArrayList(u8).init(self.allocator);
        try output.appendSlice(input[0..replace_pos]);
        try output.appendSlice(interesting);
        try output.appendSlice(input[replace_pos + replace_len ..]);

        return output.toOwnedSlice();
    }

    fn mutateBoundaryValues(self: *JsonFuzzer, input: []const u8, random: std.rand.Random) ![]u8 {
        _ = input;

        // Generate input with boundary values
        const templates = [_][]const u8{
            "[{s}]",
            "{{\"value\": {s}}}",
            "[{s}, {s}, {s}]",
        };

        const template = templates[random.intRangeAtMost(usize, 0, templates.len - 1)];
        const value = self.interesting_values[random.intRangeAtMost(usize, 0, self.interesting_values.len - 1)];

        return std.fmt.allocPrint(self.allocator, template, .{value});
    }

    fn mutateNestingAttack(self: *JsonFuzzer, input: []const u8, random: std.rand.Random) ![]u8 {
        _ = input;

        // Generate deeply nested structure
        const depth = random.intRangeAtMost(u32, 10, 1000);
        var output = std.ArrayList(u8).init(self.allocator);

        // Opening brackets
        for (0..depth) |_| {
            if (random.boolean()) {
                try output.append('[');
            } else {
                try output.appendSlice("{\"a\":");
            }
        }

        // Value in the middle
        try output.appendSlice("null");

        // Closing brackets
        var i = depth;
        while (i > 0) : (i -= 1) {
            if (output.items[i - 1] == '[') {
                try output.append(']');
            } else {
                try output.append('}');
            }
        }

        return output.toOwnedSlice();
    }

    fn selectMutationStrategy(random: std.rand.Random) MutationStrategy {
        const strategies = std.meta.tags(MutationStrategy);
        var total_weight: u32 = 0;

        for (strategies) |strategy| {
            total_weight += strategy.getWeight();
        }

        var choice = random.intRangeAtMost(u32, 0, total_weight - 1);

        for (strategies) |strategy| {
            const weight = strategy.getWeight();
            if (choice < weight) return strategy;
            choice -= weight;
        }

        return .byte_replace; // Default
    }

    fn loadCorpus(allocator: std.mem.Allocator, corpus: *std.ArrayList([]u8), dir_path: []const u8) !void {
        const dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch {
            // Directory doesn't exist, skip loading
            return;
        };
        var iter = dir.iterate();

        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            const file_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
            defer allocator.free(file_path);

            const content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch continue;
            try corpus.append(content);
        }
    }

    fn saveToCorpus(self: *JsonFuzzer, input: []const u8) !void {
        // Create corpus directory if it doesn't exist
        std.fs.cwd().makeDir(self.config.corpus_dir) catch {};

        // Generate filename based on hash
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(input);
        const hash = hasher.final();

        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{x}.json", .{ self.config.corpus_dir, hash });
        defer self.allocator.free(filename);

        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        try file.writeAll(input);
    }

    fn saveCrash(self: *JsonFuzzer, input: []const u8, err: anyerror) !void {
        // Create crashes directory
        const crashes_dir = "tests/fuzz/crashes";
        std.fs.cwd().makeDir(crashes_dir) catch {};

        const filename = try std.fmt.allocPrint(self.allocator, "{s}/crash_{d}_{s}.json", .{ crashes_dir, std.time.timestamp(), @errorName(err) });
        defer self.allocator.free(filename);

        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        try file.writeAll(input);
    }
};

/// Result of fuzzing a single input
const FuzzResult = struct {
    crashed: bool,
    timeout: bool,
    interesting: bool,
    coverage_increase: bool,
};

/// AFL++ compatible fuzzer entry point
pub export fn afl_fuzz_one(data: [*]const u8, size: usize) callconv(.C) void {
    const input = data[0..size];

    // Test all modes
    inline for ([_]zmin.ProcessingMode{ .eco, .sport, .turbo }) |mode| {
        const output = zmin.minifyWithMode(std.heap.page_allocator, input, mode) catch {
            // Error is expected for invalid input
            continue;
        };
        std.heap.page_allocator.free(output);
    }
}

test "fuzz: basic fuzzing" {
    const allocator = std.testing.allocator;

    const config = FuzzerConfig{
        .max_input_size = 1024,
        .mutations_per_seed = 10,
        .collect_corpus = false,
    };

    var fuzzer = try JsonFuzzer.init(allocator, config);
    defer fuzzer.deinit();

    // Run short fuzzing campaign
    try fuzzer.fuzz(1); // 1 second

    std.debug.print("\nFuzz test completed: {d} executions, {d} crashes\n", .{
        fuzzer.total_executions,
        fuzzer.crashes_found,
    });

    // Test should pass if no crashes found
    try std.testing.expect(fuzzer.crashes_found == 0);
}
