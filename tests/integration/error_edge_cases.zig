const std = @import("std");
const testing = std.testing;
const errors = @import("../../tools/common/errors.zig");

test "error edge case - memory exhaustion handling" {
    // Create a small allocator that will fail
    var buffer: [1024]u8 = undefined;
    var fixed_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    const limited_allocator = fixed_allocator.allocator();

    var reporter = errors.ErrorReporter.init(limited_allocator, "memory-test");

    // Try to allocate something that will fail
    const large_allocation = limited_allocator.alloc(u8, 2048);
    try testing.expectError(error.OutOfMemory, large_allocation);

    // Error reporter should still work with limited memory
    const ctx = errors.context("memory-test", "allocation-failure");
    reporter.report(errors.DevToolError.InternalError, ctx);
}

test "error edge case - filesystem permission handling" {
    const restricted_paths = [_][]const u8{
        "/root/restricted.txt",
        "/etc/shadow",
        "/sys/kernel/restricted",
    };

    var reporter = errors.ErrorReporter.init(testing.allocator, "fs-test");
    const file_ops = errors.FileOps{ .reporter = &reporter };

    for (restricted_paths) |path| {
        const result = file_ops.readFile(testing.allocator, path);

        // Should fail gracefully, not crash
        try testing.expectError(errors.DevToolError.FileNotFound, result);

        const ctx = errors.contextWithFile("fs-test", "permission-test", path);
        reporter.report(errors.DevToolError.FileNotFound, ctx);
    }
}

test "error edge case - malformed input handling" {
    var reporter = errors.ErrorReporter.init(testing.allocator, "input-test");

    const malformed_inputs = [_][]const u8{
        "", // Empty input
        "\x00\x01\x02", // Binary garbage
        "�������", // Invalid UTF-8
        "\n\n\n\n\n", // Only whitespace
        "a" ** 1024, // Very long input
    };

    for (malformed_inputs) |input| {
        // Test that error reporting can handle malformed input
        const ctx = errors.contextWithDetails("input-test", "malformed-input", input);
        reporter.report(errors.DevToolError.InvalidArguments, ctx);

        // Should not crash
    }
}

test "error edge case - concurrent error reporting" {
    const num_threads = 4;
    const errors_per_thread = 50;

    var reporter = errors.ErrorReporter.init(testing.allocator, "concurrent-test");

    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]errors.ErrorContext = undefined;

    // Initialize contexts
    for (&contexts, 0..) |*ctx, i| {
        const thread_name = try std.fmt.allocPrint(testing.allocator, "thread-{d}", .{i});
        defer testing.allocator.free(thread_name);
        ctx.* = errors.contextWithDetails("concurrent-test", "thread-operation", thread_name);
    }

    const WorkerData = struct {
        reporter: *errors.ErrorReporter,
        context: errors.ErrorContext,
        error_count: u32,
    };

    const worker_fn = struct {
        fn run(data: WorkerData) void {
            for (0..data.error_count) |_| {
                data.reporter.report(errors.DevToolError.InternalError, data.context);
                // Small delay to increase chance of race conditions
                std.time.sleep(1000); // 1 microsecond
            }
        }
    }.run;

    // Start threads
    for (&threads, 0..) |*thread, i| {
        const worker_data = WorkerData{
            .reporter = &reporter,
            .context = contexts[i],
            .error_count = errors_per_thread,
        };
        thread.* = try std.Thread.spawn(.{}, worker_fn, .{worker_data});
    }

    // Wait for completion
    for (threads) |thread| {
        thread.join();
    }

    // Should complete without crashes or deadlocks
}

test "error edge case - error context overflow" {
    var reporter = errors.ErrorReporter.init(testing.allocator, "overflow-test");

    // Create very long strings for context
    const long_tool_name = "a" ** 512;
    const long_operation = "b" ** 512;
    const long_details = "c" ** 1024;
    const long_filename = "d" ** 256;

    // Test various context creation functions with overflow
    const contexts = [_]errors.ErrorContext{
        errors.context(long_tool_name, long_operation),
        errors.contextWithDetails(long_tool_name, long_operation, long_details),
        errors.contextWithFile(long_tool_name, long_operation, long_filename),
    };

    for (contexts) |ctx| {
        // Should handle long contexts gracefully
        reporter.report(errors.DevToolError.InternalError, ctx);

        // Test formatting doesn't crash
        var buffer = std.ArrayList(u8).init(testing.allocator);
        defer buffer.deinit();

        ctx.format("", .{}, buffer.writer()) catch {
            // Format may fail, but shouldn't crash
        };
    }
}

test "error edge case - recursive error handling" {
    var reporter = errors.ErrorReporter.init(testing.allocator, "recursive-test");
    const file_ops = errors.FileOps{ .reporter = &reporter };

    // Create a scenario where error handling itself might trigger errors
    const problematic_path = "/proc/1/mem"; // Usually not readable

    // Try to read a file that will cause permission error
    const result1 = file_ops.readFile(testing.allocator, problematic_path);
    try testing.expectError(errors.DevToolError.FileNotFound, result1);

    // Try to report an error about the error (meta-error)
    const ctx = errors.contextWithFile("recursive-test", "meta-error", problematic_path);
    reporter.report(errors.DevToolError.InternalError, ctx);

    // Should not cause infinite recursion
}

test "error edge case - corrupted data handling" {
    var reporter = errors.ErrorReporter.init(testing.allocator, "corruption-test");

    // Simulate corrupted data scenarios
    var corrupted_data: [64]u8 = undefined;

    // Fill with random-looking data
    for (&corrupted_data, 0..) |*byte, i| {
        byte.* = @truncate(i * 123 + 456);
    }

    // Try to use corrupted data as strings (will likely be invalid UTF-8)
    const corrupted_string = corrupted_data[0..32];

    const ctx = errors.contextWithDetails("corruption-test", "corrupted-data", corrupted_string);
    reporter.report(errors.DevToolError.InternalError, ctx);

    // Should handle gracefully
}

test "error edge case - system resource exhaustion" {
    var reporter = errors.ErrorReporter.init(testing.allocator, "resource-test");

    // Simulate file descriptor exhaustion by trying many operations
    for (0..100) |i| {
        const temp_filename = try std.fmt.allocPrint(testing.allocator, "/tmp/test_fd_{d}.txt", .{i});
        defer testing.allocator.free(temp_filename);

        const file_ops = errors.FileOps{ .reporter = &reporter };
        const result = file_ops.readFile(testing.allocator, temp_filename);

        // Most will fail, which is expected
        if (result) |content| {
            testing.allocator.free(content);
        } else |_| {
            // Error is expected for non-existent files
            const ctx = errors.contextWithFile("resource-test", "fd-exhaustion", temp_filename);
            reporter.report(errors.DevToolError.FileNotFound, ctx);
        }
    }
}

test "error edge case - interrupt signal handling" {
    var reporter = errors.ErrorReporter.init(testing.allocator, "signal-test");

    // Simulate long-running error reporting that might be interrupted
    for (0..1000) |i| {
        const ctx = errors.contextWithDetails("signal-test", "long-operation", "processing...");
        reporter.report(errors.DevToolError.InternalError, ctx);

        // Check if we should simulate interruption
        if (i % 100 == 0) {
            // Simulate brief interruption
            std.time.sleep(1_000_000); // 1ms
        }
    }

    // Should complete despite simulated interruptions
}

test "error edge case - null pointer handling" {
    var reporter = errors.ErrorReporter.init(testing.allocator, "null-test");

    // Test with optional values that might be null
    const optional_string: ?[]const u8 = null;
    const optional_number: ?i32 = null;

    const details = if (optional_string) |s| s else "null-string";
    const number_str = if (optional_number) |n|
        try std.fmt.allocPrint(testing.allocator, "{d}", .{n})
    else
        try std.fmt.allocPrint(testing.allocator, "null-number", .{});
    defer testing.allocator.free(number_str);

    const ctx = errors.contextWithDetails("null-test", "null-handling", details);
    reporter.report(errors.DevToolError.InvalidArguments, ctx);

    // Should handle null values gracefully
}
