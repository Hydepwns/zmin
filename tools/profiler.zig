const std = @import("std");
const zmin = @import("zmin_lib");
const errors = @import("common/errors.zig");
const DevToolError = errors.DevToolError;
const ErrorReporter = errors.ErrorReporter;

const Profiler = struct {
    allocator: std.mem.Allocator,
    samples: std.ArrayList(Sample),
    current_sample: ?*Sample,
    enabled: bool,
    reporter: ErrorReporter,

    const Sample = struct {
        name: []const u8,
        start_time: u64,
        end_time: ?u64,
        memory_before: usize,
        memory_after: ?usize,
        children: std.ArrayList(Sample),
        parent: ?*Sample,

        pub fn init(allocator: std.mem.Allocator, name: []const u8, start_time: u64, memory_before: usize) Sample {
            return Sample{
                .name = name,
                .start_time = start_time,
                .end_time = null,
                .memory_before = memory_before,
                .memory_after = null,
                .children = std.ArrayList(Sample).init(allocator),
                .parent = null,
            };
        }

        pub fn deinit(self: *Sample) void {
            for (self.children.items) |*child| {
                child.deinit();
            }
            self.children.deinit();
        }

        pub fn duration(self: Sample) ?u64 {
            return if (self.end_time) |end| end - self.start_time else null;
        }

        pub fn memory_used(self: Sample) ?usize {
            return if (self.memory_after) |after| after - self.memory_before else null;
        }
    };

    pub fn init(allocator: std.mem.Allocator) Profiler {
        return Profiler{
            .allocator = allocator,
            .samples = std.ArrayList(Sample).init(allocator),
            .current_sample = null,
            .enabled = true,
            .reporter = ErrorReporter.init(allocator, "profiler"),
        };
    }

    pub fn deinit(self: *Profiler) void {
        for (self.samples.items) |*sample| {
            sample.deinit();
        }
        self.samples.deinit();
    }

    pub fn startSample(self: *Profiler, name: []const u8) !void {
        if (!self.enabled) return;

        var timer = try std.time.Timer.start();
        const memory_before = self.getCurrentMemoryUsage();

        var sample = Sample.init(self.allocator, name, timer.read(), memory_before);
        
        if (self.current_sample) |current| {
            sample.parent = current;
            try current.children.append(sample);
            self.current_sample = &current.children.items[current.children.items.len - 1];
        } else {
            try self.samples.append(sample);
            self.current_sample = &self.samples.items[self.samples.items.len - 1];
        }
    }

    pub fn endSample(self: *Profiler) void {
        if (!self.enabled or self.current_sample == null) return;

        var timer = std.time.Timer.start() catch return;
        const memory_after = self.getCurrentMemoryUsage();

        if (self.current_sample) |sample| {
            sample.end_time = timer.read();
            sample.memory_after = memory_after;
        }

        // Move back to parent
        if (self.current_sample) |sample| {
            self.current_sample = sample.parent;
        }
    }

    fn getCurrentMemoryUsage(self: *Profiler) usize {
        _ = self;
        // Try to read from /proc/self/status on Linux
        const status = std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/proc/self/status", 4096) catch return 0;
        defer std.heap.page_allocator.free(status);

        var lines = std.mem.splitSequence(u8, status, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "VmRSS:")) {
                var parts = std.mem.splitSequence(u8, line, " ");
                _ = parts.next(); // Skip "VmRSS:"
                while (parts.next()) |part| {
                    if (part.len > 0 and std.ascii.isDigit(part[0])) {
                        const kb_value = std.fmt.parseInt(usize, part, 10) catch return 0;
                        return kb_value * 1024; // Convert KB to bytes
                    }
                }
            }
        }
        return 0;
    }

    pub fn printReport(self: *Profiler) void {
        if (!self.enabled) return;

        std.log.info("=== Performance Profile Report ===", .{});

        for (self.samples.items) |sample| {
            self.printSample(sample, 0);
        }
    }

    fn printSample(self: *Profiler, sample: Sample, depth: usize) void {
        // Create indent string
        var indent_buf: [64]u8 = undefined;
        const indent_len = @min(depth * 2, indent_buf.len);
        for (0..indent_len) |i| {
            indent_buf[i] = ' ';
        }
        const indent = indent_buf[0..indent_len];
        
        const duration = sample.duration();
        const memory = sample.memory_used();

        if (duration) |dur| {
            const ms = @as(f64, @floatFromInt(dur)) / 1_000_000.0;
            std.log.info("{s}{s}: {d:.2}ms", .{ indent, sample.name, ms });

            if (memory) |mem| {
                std.log.info("{s}  Memory: {d} bytes", .{ indent, mem });
            }
        } else {
            std.log.info("{s}{s}: <running>", .{ indent, sample.name });
        }

        for (sample.children.items) |child| {
            self.printSample(child, depth + 1);
        }
    }

    pub fn exportToJson(self: *Profiler, path: []const u8) !void {
        if (!self.enabled) return;

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll("{\n");
        try file.writeAll("  \"samples\": [\n");

        for (self.samples.items, 0..) |sample, i| {
            if (i > 0) try file.writeAll(",\n");
            try self.writeSampleToJson(file, sample, 2);
        }

        try file.writeAll("\n  ]\n");
        try file.writeAll("}\n");
    }

    fn writeSampleToJson(self: *Profiler, file: std.fs.File, sample: Sample, indent: usize) !void {
        // Create indent string
        var indent_buf: [256]u8 = undefined;
        const indent_len = @min(indent, indent_buf.len);
        for (0..indent_len) |i| {
            indent_buf[i] = ' ';
        }
        const indent_str = indent_buf[0..indent_len];
        
        try file.writer().print("{s}{{\n", .{indent_str});
        try file.writer().print("{s}  \"name\": \"{s}\",\n", .{ indent_str, sample.name });
        try file.writer().print("{s}  \"start_time\": {d},\n", .{ indent_str, sample.start_time });

        if (sample.end_time) |end_time| {
            try file.writer().print("{s}  \"end_time\": {d},\n", .{ indent_str, end_time });
            try file.writer().print("{s}  \"duration\": {d},\n", .{ indent_str, end_time - sample.start_time });
        }

        try file.writer().print("{s}  \"memory_before\": {d},\n", .{ indent_str, sample.memory_before });

        if (sample.memory_after) |memory_after| {
            try file.writer().print("{s}  \"memory_after\": {d},\n", .{ indent_str, memory_after });
            try file.writer().print("{s}  \"memory_used\": {d},\n", .{ indent_str, memory_after - sample.memory_before });
        }

        if (sample.children.items.len > 0) {
            try file.writer().print("{s}  \"children\": [\n", .{indent_str});
            for (sample.children.items, 0..) |child, i| {
                if (i > 0) try file.writer().print(",\n", .{});
                try self.writeSampleToJson(file, child, indent + 4);
            }
            try file.writer().print("\n{s}  ]\n", .{indent_str});
        }

        try file.writer().print("{s}}}", .{indent_str});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var input_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;
    var json_output: ?[]const u8 = null;
    var iterations: u32 = 100;

    // Create error reporter for argument parsing
    var reporter = ErrorReporter.init(allocator, "profiler");

    // Parse command line arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--input") or std.mem.eql(u8, arg, "-i")) {
            if (i + 1 >= args.len) {
                reporter.report(DevToolError.MissingArgument, errors.contextWithDetails(
                    "profiler", "parsing arguments", "Missing input file path"
                ));
                return DevToolError.MissingArgument;
            }
            input_file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            if (i + 1 >= args.len) {
                reporter.report(DevToolError.MissingArgument, errors.contextWithDetails(
                    "profiler", "parsing arguments", "Missing output file path"
                ));
                return DevToolError.MissingArgument;
            }
            output_file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            if (i + 1 >= args.len) {
                reporter.report(DevToolError.MissingArgument, errors.contextWithDetails(
                    "profiler", "parsing arguments", "Missing JSON output file path"
                ));
                return DevToolError.MissingArgument;
            }
            json_output = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--iterations") or std.mem.eql(u8, arg, "-n")) {
            if (i + 1 >= args.len) {
                reporter.report(DevToolError.MissingArgument, errors.contextWithDetails(
                    "profiler", "parsing arguments", "Missing iteration count"
                ));
                return DevToolError.MissingArgument;
            }
            iterations = try std.fmt.parseInt(u32, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else {
            reporter.report(DevToolError.UnknownCommand, errors.contextWithDetails(
                "profiler", "parsing arguments", arg
            ));
            return DevToolError.UnknownCommand;
        }
    }

    var profiler = Profiler.init(allocator);
    defer profiler.deinit();

    // Read input
    const input = if (input_file) |file_path| blk: {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    } else blk: {
        // Use sample input
        break :blk "function example() { const message = \"Hello, World!\"; console.log(message); return message; }";
    };

    defer if (input_file != null) allocator.free(input);

    std.log.info("Starting performance profiling with {d} iterations", .{iterations});

    // Profile different modes
    const modes = [_]zmin.ProcessingMode{ .eco, .sport, .turbo };

    for (modes) |mode| {
        try profiler.startSample(@tagName(mode));

        for (0..iterations) |j| {
            try profiler.startSample("iteration");

            const result = try zmin.minify(allocator, input, mode);
            defer allocator.free(result);

            profiler.endSample();

            if (j % 10 == 0) {
                std.log.info("Completed {d}/{d} iterations for {s} mode", .{ j + 1, iterations, @tagName(mode) });
            }
        }

        profiler.endSample();
    }

    // Print report
    profiler.printReport();

    // Export to JSON if requested
    if (json_output) |json_path| {
        try profiler.exportToJson(json_path);
        std.log.info("Profile exported to: {s}", .{json_path});
    }

    // Write output if requested
    if (output_file) |out_path| {
        const file = try std.fs.cwd().createFile(out_path, .{});
        defer file.close();

        // Write the last result from turbo mode
        const result = try zmin.minify(allocator, input, .turbo);
        defer allocator.free(result);

        try file.writeAll(result);
        std.log.info("Output written to: {s}", .{out_path});
    }

    std.log.info("Profiling completed", .{});
}

fn printUsage() void {
    std.log.info("zmin Profiler Usage:", .{});
    std.log.info("  --input, -i <file>     Input file to process", .{});
    std.log.info("  --output, -o <file>    Output file for minified result", .{});
    std.log.info("  --json, -j <file>      Export profile to JSON file", .{});
    std.log.info("  --iterations, -n <num> Number of iterations (default: 100)", .{});
    std.log.info("  --help, -h             Show this help", .{});
}
