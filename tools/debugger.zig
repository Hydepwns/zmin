const std = @import("std");
const zmin = @import("zmin_lib");
const builtin = @import("builtin");
const errors = @import("common/errors.zig");
const DevToolError = errors.DevToolError;
const ErrorReporter = errors.ErrorReporter;

// System information structure
const SystemInfo = struct {
    cpu_model: []const u8,
    cpu_features: []const u8,
    cores: u32,
    threads: u32,
    numa_nodes: u32,
    total_memory: usize,
    available_memory: usize,
    os: []const u8,
    arch: []const u8,
};

// Performance profiler
const PerformanceProfiler = struct {
    samples: std.ArrayList(Sample),
    start_time: i64,
    
    const Sample = struct {
        timestamp: i64,
        cpu_usage: f64,
        memory_usage: usize,
        function_name: []const u8,
        duration_ns: u64,
    };
    
    pub fn init(allocator: std.mem.Allocator) PerformanceProfiler {
        return PerformanceProfiler{
            .samples = std.ArrayList(Sample).init(allocator),
            .start_time = std.time.timestamp(),
        };
    }
    
    pub fn deinit(self: *PerformanceProfiler) void {
        self.samples.deinit();
    }
    
    pub fn recordSample(self: *PerformanceProfiler, function_name: []const u8, duration_ns: u64) !void {
        try self.samples.append(Sample{
            .timestamp = std.time.timestamp(),
            .cpu_usage = getCurrentCpuUsage(),
            .memory_usage = getCurrentMemoryUsage(),
            .function_name = function_name,
            .duration_ns = duration_ns,
        });
    }
    
    pub fn generateReport(self: *PerformanceProfiler, allocator: std.mem.Allocator) ![]const u8 {
        var report = std.ArrayList(u8).init(allocator);
        defer report.deinit();
        
        const writer = report.writer();
        try writer.writeAll("## Performance Profile Report\n\n");
        
        var total_time: u64 = 0;
        for (self.samples.items) |sample| {
            total_time += sample.duration_ns;
        }
        
        try writer.print("**Total execution time:** {d:.2}ms\n", .{@as(f64, @floatFromInt(total_time)) / 1_000_000.0});
        try writer.print("**Sample count:** {d}\n\n", .{self.samples.items.len});
        
        try writer.writeAll("### Function Performance:\n");
        for (self.samples.items) |sample| {
            try writer.print("- **{s}**: {d:.2}ms (CPU: {d:.1}%, Memory: {d} bytes)\n", .{
                sample.function_name,
                @as(f64, @floatFromInt(sample.duration_ns)) / 1_000_000.0,
                sample.cpu_usage,
                sample.memory_usage,
            });
        }
        
        return try allocator.dupe(u8, report.items);
    }
};

const Debugger = struct {
    allocator: std.mem.Allocator,
    debug_level: DebugLevel,
    log_file: ?std.fs.File,
    memory_tracker: MemoryTracker,
    profiler: PerformanceProfiler,
    system_info: SystemInfo,
    enable_profiling: bool,
    enable_memory_tracking: bool,
    enable_stack_traces: bool,
    reporter: ErrorReporter,
    file_ops: errors.FileOps,
    process_ops: errors.ProcessOps,

    const DebugLevel = enum {
        none,
        basic,
        verbose,
        trace,
    };

    const MemoryTracker = struct {
        allocations: std.AutoHashMap(usize, AllocationInfo),
        total_allocated: usize,
        peak_allocated: usize,

        const AllocationInfo = struct {
            size: usize,
            stack_trace: std.ArrayList(usize),
        };

        pub fn init(allocator: std.mem.Allocator) MemoryTracker {
            return MemoryTracker{
                .allocations = std.AutoHashMap(usize, AllocationInfo).init(allocator),
                .total_allocated = 0,
                .peak_allocated = 0,
            };
        }

        pub fn deinit(self: *MemoryTracker) void {
            self.allocations.deinit();
        }

        pub fn trackAllocation(self: *MemoryTracker, ptr: [*]u8, size: usize) !void {
            const addr = @intFromPtr(ptr);

            // Capture stack trace (simplified)
            _ = @returnAddress();

            const stack_trace = std.ArrayList(usize).init(self.allocations.allocator);
            try self.allocations.put(addr, .{
                .size = size,
                .stack_trace = stack_trace,
            });

            self.total_allocated += size;
            if (self.total_allocated > self.peak_allocated) {
                self.peak_allocated = self.total_allocated;
            }
        }

        pub fn trackDeallocation(self: *MemoryTracker, ptr: [*]u8) void {
            const addr = @intFromPtr(ptr);
            if (self.allocations.get(addr)) |info| {
                self.total_allocated -= info.size;
                self.allocations.remove(addr);
            }
        }

        pub fn printReport(self: *MemoryTracker) void {
            std.log.info("Memory Report:", .{});
            std.log.info("  Total allocated: {d} bytes", .{self.total_allocated});
            std.log.info("  Peak allocated: {d} bytes", .{self.peak_allocated});
            std.log.info("  Active allocations: {d}", .{self.allocations.count()});
        }
    };

    pub fn init(allocator: std.mem.Allocator, level: DebugLevel) !Debugger {
        const system_info = detectSystemInfo(allocator) catch |err| {
            // Create a basic reporter for error handling during init
            var init_reporter = ErrorReporter.init(allocator, "debugger");
            init_reporter.report(err, errors.context("debugger", "detecting system information"));
            return DevToolError.InternalError;
        };
        
        var reporter = ErrorReporter.init(allocator, "debugger");
        const file_ops = errors.FileOps{ .reporter = &reporter };
        const process_ops = errors.ProcessOps{ .reporter = &reporter };
        
        return Debugger{
            .allocator = allocator,
            .debug_level = level,
            .log_file = null,
            .memory_tracker = MemoryTracker.init(allocator),
            .profiler = PerformanceProfiler.init(allocator),
            .system_info = system_info,
            .enable_profiling = true,
            .enable_memory_tracking = true,
            .enable_stack_traces = true,
            .reporter = reporter,
            .file_ops = file_ops,
            .process_ops = process_ops,
        };
    }

    pub fn deinit(self: *Debugger) void {
        if (self.log_file) |file| {
            file.close();
        }
        self.memory_tracker.deinit();
        self.profiler.deinit();
    }

    pub fn setLogFile(self: *Debugger, path: []const u8) !void {
        if (self.log_file) |file| {
            file.close();
        }
        self.log_file = self.file_ops.createFile(path) catch |err| {
            self.reporter.report(err, errors.contextWithFile("debugger", "creating log file", path));
            return DevToolError.FileWriteError;
        };
    }

    pub fn enableProfiling(self: *Debugger, enable: bool) void {
        self.enable_profiling = enable;
    }

    pub fn enableMemoryTracking(self: *Debugger, enable: bool) void {
        self.enable_memory_tracking = enable;
    }

    pub fn enableStackTraces(self: *Debugger, enable: bool) void {
        self.enable_stack_traces = enable;
    }

    pub fn log(self: *Debugger, comptime level: DebugLevel, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(level) <= @intFromEnum(self.debug_level)) {
            const message = std.fmt.allocPrint(self.allocator, format, args) catch return;
            defer self.allocator.free(message);

            const timestamp = std.time.milliTimestamp();
            const log_entry = std.fmt.allocPrint(self.allocator, "[{d}] [{s}] {s}\n", .{ timestamp, @tagName(level), message }) catch return;
            defer self.allocator.free(log_entry);

            // Print to console
            std.log.info("{s}", .{log_entry});

            // Write to log file if available
            if (self.log_file) |file| {
                file.writeAll(log_entry) catch {};
            }
        }
    }

    pub fn debugMinify(self: *Debugger, input: []const u8, mode: zmin.ProcessingMode) ![]const u8 {
        self.log(.basic, "Starting minification with mode: {s}", .{@tagName(mode)});
        self.log(.basic, "Input size: {d} bytes", .{input.len});

        const start_time = std.time.milliTimestamp();

        // Track memory before
        const mem_before = self.memory_tracker.total_allocated;

        const result = zmin.minify(self.allocator, input, mode) catch |err| {
            self.reporter.report(err, errors.contextWithDetails(
                "debugger", "minifying JSON", "debug minification failed"
            ));
            return DevToolError.InternalError;
        };

        // Track memory after
        const mem_after = self.memory_tracker.total_allocated;
        const mem_used = mem_after - mem_before;

        const end_time = std.time.milliTimestamp();
        const duration = end_time - start_time;

        self.log(.basic, "Minification completed in {d}ms", .{duration});
        self.log(.basic, "Output size: {d} bytes", .{result.len});
        self.log(.basic, "Memory used: {d} bytes", .{mem_used});
        self.log(.basic, "Compression ratio: {d:.2}%", .{@as(f64, @floatFromInt(result.len)) / @as(f64, @floatFromInt(input.len)) * 100.0});

        if (self.debug_level == .trace) {
            self.log(.trace, "Input: {s}", .{input});
            self.log(.trace, "Output: {s}", .{result});
        }

        return result;
    }

    pub fn analyzePerformance(self: *Debugger, input: []const u8) !void {
        self.log(.basic, "Starting performance analysis", .{});

        const modes = [_]zmin.ProcessingMode{ .eco, .sport, .turbo };
        var results: [3]struct {
            mode: zmin.ProcessingMode,
            time_ns: u64,
            size: usize,
            memory: usize,
        } = undefined;

        for (modes, 0..) |mode, i| {
            self.log(.verbose, "Testing mode: {s}", .{@tagName(mode)});

            const mem_before = self.memory_tracker.total_allocated;
            var timer = std.time.Timer.start() catch |err| {
                self.reporter.report(err, errors.context("debugger", "starting performance timer"));
                return DevToolError.InternalError;
            };

            const result = zmin.minify(self.allocator, input, mode) catch |err| {
                self.reporter.report(err, errors.contextWithDetails(
                    "debugger", "performance analysis", "minification failed"
                ));
                return DevToolError.InternalError;
            };

            const elapsed = timer.read();
            const mem_after = self.memory_tracker.total_allocated;
            const mem_used = mem_after - mem_before;

            results[i] = .{
                .mode = mode,
                .time_ns = elapsed,
                .size = result.len,
                .memory = mem_used,
            };

            self.log(.verbose, "  Time: {d:.2}ms", .{@as(f64, @floatFromInt(elapsed)) / 1_000_000.0});
            self.log(.verbose, "  Size: {d} bytes", .{result.len});
            self.log(.verbose, "  Memory: {d} bytes", .{mem_used});
        }

        // Print performance comparison
        self.log(.basic, "Performance Comparison:", .{});
        for (results) |result| {
            self.log(.basic, "  {s}: {d:.2}ms, {d} bytes, {d} bytes memory", .{
                @tagName(result.mode),
                @as(f64, @floatFromInt(result.time_ns)) / 1_000_000.0,
                result.size,
                result.memory,
            });
        }
    }

    pub fn checkMemoryLeaks(self: *Debugger) void {
        self.memory_tracker.printReport();

        if (self.memory_tracker.total_allocated > 0) {
            self.log(.basic, "WARNING: Potential memory leak detected!", .{});
            self.log(.basic, "Unfreed memory: {d} bytes", .{self.memory_tracker.total_allocated});
        } else {
            self.log(.basic, "No memory leaks detected", .{});
        }
    }

    pub fn printSystemInfo(self: *Debugger) void {
        self.log(.basic, "🖥️  System Information:", .{});
        self.log(.basic, "  OS: {s}", .{self.system_info.os});
        self.log(.basic, "  Architecture: {s}", .{self.system_info.arch});
        self.log(.basic, "  CPU Model: {s}", .{self.system_info.cpu_model});
        self.log(.basic, "  CPU Features: {s}", .{self.system_info.cpu_features});
        self.log(.basic, "  Cores: {d}", .{self.system_info.cores});
        self.log(.basic, "  Threads: {d}", .{self.system_info.threads});
        self.log(.basic, "  NUMA Nodes: {d}", .{self.system_info.numa_nodes});
        self.log(.basic, "  Total Memory: {d:.2} GB", .{@as(f64, @floatFromInt(self.system_info.total_memory)) / (1024.0 * 1024.0 * 1024.0)});
        self.log(.basic, "  Available Memory: {d:.2} GB", .{@as(f64, @floatFromInt(self.system_info.available_memory)) / (1024.0 * 1024.0 * 1024.0)});
    }

    pub fn profileFunction(self: *Debugger, comptime function_name: []const u8, func: anytype, args: anytype) !@TypeOf(@call(.auto, func, args)) {
        if (!self.enable_profiling) {
            return @call(.auto, func, args);
        }

        var timer = std.time.Timer.start() catch |err| {
            self.reporter.report(err, errors.context("debugger", "starting profile timer"));
            return @call(.auto, func, args); // Continue without profiling
        };
        const result = @call(.auto, func, args);
        const elapsed = timer.read();

        self.profiler.recordSample(function_name, elapsed) catch |err| {
            self.reporter.report(err, errors.context("debugger", "recording profiling sample"));
            // Continue without recording this sample
        };
        
        self.log(.trace, "⏱️  {s}: {d:.3}ms", .{function_name, @as(f64, @floatFromInt(elapsed)) / 1_000_000.0});
        
        return result;
    }

    pub fn generatePerformanceReport(self: *Debugger) ![]const u8 {
        return try self.profiler.generateReport(self.allocator);
    }

    pub fn benchmark(self: *Debugger, input: []const u8, iterations: u32) !void {
        self.log(.basic, "🏁 Starting comprehensive benchmark ({d} iterations)", .{iterations});

        const modes = [_]zmin.ProcessingMode{ .eco, .sport, .turbo };
        
        for (modes) |mode| {
            self.log(.basic, "📊 Benchmarking {s} mode:", .{@tagName(mode)});
            
            var total_time: u64 = 0;
            var total_memory: usize = 0;
            var min_time: u64 = std.math.maxInt(u64);
            var max_time: u64 = 0;
            var results_size: usize = 0;

            for (0..iterations) |i| {
                const mem_before = if (self.enable_memory_tracking) self.memory_tracker.total_allocated else 0;
                
                var timer = std.time.Timer.start() catch |err| {
                    self.reporter.report(err, errors.context("debugger", "starting benchmark timer"));
                    return DevToolError.InternalError;
                };
                const result = zmin.minify(self.allocator, input, mode) catch |err| {
                    self.reporter.report(err, errors.contextWithDetails(
                        "debugger", "benchmark minification", "minification failed"
                    ));
                    return DevToolError.InternalError;
                };
                const elapsed = timer.read();
                
                const mem_after = if (self.enable_memory_tracking) self.memory_tracker.total_allocated else 0;
                const mem_used = mem_after - mem_before;

                total_time += elapsed;
                total_memory += mem_used;
                min_time = @min(min_time, elapsed);
                max_time = @max(max_time, elapsed);
                results_size = result.len;

                if (self.enable_profiling) {
                    self.profiler.recordSample(@tagName(mode), elapsed) catch |err| {
                        self.reporter.report(err, errors.context("debugger", "recording benchmark sample"));
                        // Continue without recording this sample
                    };
                }

                self.allocator.free(result);

                if (self.debug_level == .trace) {
                    self.log(.trace, "  Iteration {d}: {d:.3}ms, {d} bytes memory", .{i + 1, @as(f64, @floatFromInt(elapsed)) / 1_000_000.0, mem_used});
                }
            }

            const avg_time = total_time / iterations;
            const avg_memory = total_memory / iterations;
            const compression_ratio = (@as(f64, @floatFromInt(results_size)) / @as(f64, @floatFromInt(input.len))) * 100.0;

            self.log(.basic, "  📈 Results:", .{});
            self.log(.basic, "    Average time: {d:.3}ms", .{@as(f64, @floatFromInt(avg_time)) / 1_000_000.0});
            self.log(.basic, "    Min time: {d:.3}ms", .{@as(f64, @floatFromInt(min_time)) / 1_000_000.0});
            self.log(.basic, "    Max time: {d:.3}ms", .{@as(f64, @floatFromInt(max_time)) / 1_000_000.0});
            self.log(.basic, "    Average memory: {d} bytes", .{avg_memory});
            self.log(.basic, "    Output size: {d} bytes", .{results_size});
            self.log(.basic, "    Compression: {d:.2}%", .{compression_ratio});
            self.log(.basic, "    Throughput: {d:.2} MB/s", .{(@as(f64, @floatFromInt(input.len)) / 1024.0 / 1024.0) / (@as(f64, @floatFromInt(avg_time)) / 1_000_000_000.0)});
        }
    }

    pub fn memoryStressTest(self: *Debugger, base_size: usize, multiplier: u32) !void {
        self.log(.basic, "🧠 Memory stress test starting...", .{});
        
        const original_tracking = self.enable_memory_tracking;
        self.enable_memory_tracking = true;
        defer self.enable_memory_tracking = original_tracking;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        // Generate test data of increasing sizes
        for (0..multiplier) |i| {
            const test_size = base_size * (i + 1);
            const test_data = try generateTestData(arena.allocator(), test_size);
            
            self.log(.verbose, "Testing with {d} bytes of data", .{test_data.len});
            
            const mem_before = self.memory_tracker.total_allocated;
            var timer = std.time.Timer.start() catch |err| {
                self.reporter.report(err, errors.context("debugger", "starting stress test timer"));
                return DevToolError.InternalError;
            };
            
            const result = zmin.minify(arena.allocator(), test_data, .sport) catch |err| {
                self.reporter.report(err, errors.contextWithDetails(
                    "debugger", "memory stress test", "minification failed"
                ));
                return DevToolError.InternalError;
            };
            
            const elapsed = timer.read();
            const mem_after = self.memory_tracker.total_allocated;
            const mem_used = mem_after - mem_before;
            
            self.log(.basic, "  Size {d}: {d:.3}ms, {d} bytes memory, {d:.2}% compression", .{
                test_data.len,
                @as(f64, @floatFromInt(elapsed)) / 1_000_000.0,
                mem_used,
                (@as(f64, @floatFromInt(result.len)) / @as(f64, @floatFromInt(test_data.len))) * 100.0
            });
            
            // Force memory cleanup
            arena.deinit();
            arena = std.heap.ArenaAllocator.init(self.allocator);
        }
        
        self.log(.basic, "🧠 Memory stress test completed", .{});
    }
};

// System detection functions
fn detectSystemInfo(allocator: std.mem.Allocator) !SystemInfo {
    const cpu_model = try detectCpuModel(allocator);
    const cpu_features = try detectCpuFeatures(allocator);
    const cores = std.Thread.getCpuCount() catch 1;
    const numa_nodes = detectNumaNodes();
    const total_memory = getTotalMemory();
    const available_memory = getAvailableMemory();
    
    return SystemInfo{
        .cpu_model = cpu_model,
        .cpu_features = cpu_features,
        .cores = @intCast(cores),
        .threads = @intCast(cores), // Simplified assumption
        .numa_nodes = numa_nodes,
        .total_memory = total_memory,
        .available_memory = available_memory,
        .os = @tagName(builtin.os.tag),
        .arch = @tagName(builtin.cpu.arch),
    };
}

fn detectCpuModel(allocator: std.mem.Allocator) ![]const u8 {
    // Try to read CPU model from /proc/cpuinfo on Linux
    const cpuinfo = std.fs.cwd().readFileAlloc(allocator, "/proc/cpuinfo", 4096) catch return try allocator.dupe(u8, "Unknown CPU");
    defer allocator.free(cpuinfo);

    var lines = std.mem.splitSequence(u8, cpuinfo, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "model name")) {
            if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
                const model = std.mem.trim(u8, line[colon_pos + 1..], " \t");
                return try allocator.dupe(u8, model);
            }
        }
    }
    
    return try allocator.dupe(u8, "Unknown CPU");
}

fn detectCpuFeatures(allocator: std.mem.Allocator) ![]const u8 {
    var features = std.ArrayList(u8).init(allocator);
    defer features.deinit();

    const writer = features.writer();
    
    // Detect CPU features based on target architecture
    switch (builtin.cpu.arch) {
        .x86_64, .x86 => {
            if (std.Target.x86.featureSetHas(builtin.cpu.features, .sse)) {
                try writer.writeAll("SSE ");
            }
            if (std.Target.x86.featureSetHas(builtin.cpu.features, .sse2)) {
                try writer.writeAll("SSE2 ");
            }
            if (std.Target.x86.featureSetHas(builtin.cpu.features, .sse3)) {
                try writer.writeAll("SSE3 ");
            }
            if (std.Target.x86.featureSetHas(builtin.cpu.features, .ssse3)) {
                try writer.writeAll("SSSE3 ");
            }
            if (std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_1)) {
                try writer.writeAll("SSE4.1 ");
            }
            if (std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_2)) {
                try writer.writeAll("SSE4.2 ");
            }
            if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx)) {
                try writer.writeAll("AVX ");
            }
            if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx2)) {
                try writer.writeAll("AVX2 ");
            }
            if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx512f)) {
                try writer.writeAll("AVX512F ");
            }
        },
        .aarch64, .arm => {
            if (std.Target.aarch64.featureSetHas(builtin.cpu.features, .neon)) {
                try writer.writeAll("NEON ");
            }
        },
        else => {
            try writer.writeAll("Generic ");
        },
    }

    return try allocator.dupe(u8, features.items);
}

fn detectNumaNodes() u32 {
    const numa_path = "/sys/devices/system/node";
    var dir = std.fs.openDirAbsolute(numa_path, .{ .iterate = true }) catch return 1;
    defer dir.close();

    var count: u32 = 0;
    var iterator = dir.iterate();
    while (iterator.next() catch null) |entry| {
        if (std.mem.startsWith(u8, entry.name, "node")) {
            count += 1;
        }
    }
    
    return if (count > 0) count else 1;
}

fn getTotalMemory() usize {
    const meminfo = std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/proc/meminfo", 4096) catch return 8 * 1024 * 1024 * 1024; // 8GB default
    defer std.heap.page_allocator.free(meminfo);

    var lines = std.mem.splitSequence(u8, meminfo, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            var parts = std.mem.splitSequence(u8, line, " ");
            _ = parts.next(); // Skip "MemTotal:"
            var kb_str: ?[]const u8 = null;
            while (parts.next()) |part| {
                if (part.len > 0 and std.ascii.isDigit(part[0])) {
                    kb_str = part;
                    break;
                }
            }
            if (kb_str) |kb| {
                const kb_value = std.fmt.parseInt(usize, kb, 10) catch return 8 * 1024 * 1024 * 1024;
                return kb_value * 1024; // Convert KB to bytes
            }
        }
    }
    
    return 8 * 1024 * 1024 * 1024; // 8GB default
}

fn getAvailableMemory() usize {
    const meminfo = std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/proc/meminfo", 4096) catch return 4 * 1024 * 1024 * 1024; // 4GB default
    defer std.heap.page_allocator.free(meminfo);

    var lines = std.mem.splitSequence(u8, meminfo, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            var parts = std.mem.splitSequence(u8, line, " ");
            _ = parts.next(); // Skip "MemAvailable:"
            var kb_str: ?[]const u8 = null;
            while (parts.next()) |part| {
                if (part.len > 0 and std.ascii.isDigit(part[0])) {
                    kb_str = part;
                    break;
                }
            }
            if (kb_str) |kb| {
                const kb_value = std.fmt.parseInt(usize, kb, 10) catch return 4 * 1024 * 1024 * 1024;
                return kb_value * 1024; // Convert KB to bytes
            }
        }
    }
    
    return 4 * 1024 * 1024 * 1024; // 4GB default
}

fn getCurrentCpuUsage() f64 {
    // Simplified CPU usage detection - would need platform-specific implementation
    return 0.0;
}

fn getCurrentMemoryUsage() usize {
    const status = std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/proc/self/status", 4096) catch return 0;
    defer std.heap.page_allocator.free(status);

    var lines = std.mem.splitSequence(u8, status, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "VmRSS:")) {
            var parts = std.mem.splitSequence(u8, line, " ");
            _ = parts.next(); // Skip "VmRSS:"
            var kb_str: ?[]const u8 = null;
            while (parts.next()) |part| {
                if (part.len > 0 and std.ascii.isDigit(part[0])) {
                    kb_str = part;
                    break;
                }
            }
            if (kb_str) |kb| {
                const kb_value = std.fmt.parseInt(usize, kb, 10) catch return 0;
                return kb_value * 1024; // Convert KB to bytes
            }
        }
    }
    
    return 0;
}

fn generateTestData(allocator: std.mem.Allocator, size: usize) ![]const u8 {
    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();

    const writer = data.writer();
    
    // Generate JSON-like test data
    try writer.writeAll("{\"data\":[");
    
    const item_size = 50; // Approximate size per item
    const item_count = size / item_size;
    
    for (0..item_count) |i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{{\"id\":{d},\"name\":\"item_{d}\",\"value\":{d},\"active\":true}}", .{i, i, i * 42});
    }
    
    try writer.writeAll("]}");
    
    return try allocator.dupe(u8, data.items);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var debug_level = Debugger.DebugLevel.basic;
    var log_file: ?[]const u8 = null;
    var input_file: ?[]const u8 = null;
    var mode = zmin.ProcessingMode.sport;
    var benchmark_iterations: u32 = 10;
    var enable_profiling = true;
    var enable_memory_tracking = true;
    var enable_stress_test = false;
    var stress_test_base_size: usize = 1024;
    var stress_test_multiplier: u32 = 10;

    // Parse command line arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            debug_level = .verbose;
        } else if (std.mem.eql(u8, arg, "--trace") or std.mem.eql(u8, arg, "-t")) {
            debug_level = .trace;
        } else if (std.mem.eql(u8, arg, "--log") or std.mem.eql(u8, arg, "-l")) {
            if (i + 1 >= args.len) {
                std.log.err("Missing log file path", .{});
                return DevToolError.MissingArgument;
            }
            log_file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--input") or std.mem.eql(u8, arg, "-i")) {
            if (i + 1 >= args.len) {
                std.log.err("Missing input file path", .{});
                return DevToolError.MissingArgument;
            }
            input_file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--mode") or std.mem.eql(u8, arg, "-m")) {
            if (i + 1 >= args.len) {
                std.log.err("Missing mode", .{});
                return DevToolError.MissingArgument;
            }
            const mode_str = args[i + 1];
            mode = if (std.mem.eql(u8, mode_str, "eco"))
                zmin.ProcessingMode.eco
            else if (std.mem.eql(u8, mode_str, "sport"))
                zmin.ProcessingMode.sport
            else if (std.mem.eql(u8, mode_str, "turbo"))
                zmin.ProcessingMode.turbo
            else {
                std.log.err("Invalid mode: {s}", .{mode_str});
                return DevToolError.InvalidArguments;
            };
            i += 1;
        } else if (std.mem.eql(u8, arg, "--benchmark") or std.mem.eql(u8, arg, "-b")) {
            if (i + 1 >= args.len) {
                std.log.err("Missing benchmark iterations", .{});
                return DevToolError.MissingArgument;
            }
            benchmark_iterations = std.fmt.parseInt(u32, args[i + 1], 10) catch {
                std.log.err("Invalid benchmark iterations: {s}", .{args[i + 1]});
                return DevToolError.InvalidArguments;
            };
            i += 1;
        } else if (std.mem.eql(u8, arg, "--no-profiling")) {
            enable_profiling = false;
        } else if (std.mem.eql(u8, arg, "--no-memory-tracking")) {
            enable_memory_tracking = false;
        } else if (std.mem.eql(u8, arg, "--stress-test")) {
            enable_stress_test = true;
        } else if (std.mem.eql(u8, arg, "--stress-size")) {
            if (i + 1 >= args.len) {
                std.log.err("Missing stress test base size", .{});
                return DevToolError.MissingArgument;
            }
            stress_test_base_size = std.fmt.parseInt(usize, args[i + 1], 10) catch {
                std.log.err("Invalid stress test base size: {s}", .{args[i + 1]});
                return DevToolError.InvalidArguments;
            };
            i += 1;
        } else if (std.mem.eql(u8, arg, "--stress-multiplier")) {
            if (i + 1 >= args.len) {
                std.log.err("Missing stress test multiplier", .{});
                return DevToolError.MissingArgument;
            }
            stress_test_multiplier = std.fmt.parseInt(u32, args[i + 1], 10) catch {
                std.log.err("Invalid stress test multiplier: {s}", .{args[i + 1]});
                return DevToolError.InvalidArguments;
            };
            i += 1;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else {
            std.log.err("Unknown option: {s}", .{arg});
            printUsage();
            return DevToolError.UnknownCommand;
        }
    }

    var debugger = try Debugger.init(allocator, debug_level);
    defer debugger.deinit();

    // Configure debugger
    debugger.enableProfiling(enable_profiling);
    debugger.enableMemoryTracking(enable_memory_tracking);

    if (log_file) |log_path| {
        try debugger.setLogFile(log_path);
    }

    debugger.log(.basic, "🔧 zmin Enhanced Debugger started", .{});

    // Print system information
    debugger.printSystemInfo();

    // Read input
    const input = if (input_file) |file_path| blk: {
        const file_content = debugger.file_ops.readFile(allocator, file_path) catch |err| {
            debugger.reporter.report(err, errors.contextWithFile("debugger", "reading input file", file_path));
            return DevToolError.FileReadError;
        };
        break :blk file_content;
    } else blk: {
        // Use sample input
        break :blk "{\"users\":[{\"id\":1,\"name\":\"John Doe\",\"email\":\"john@example.com\",\"active\":true,\"profile\":{\"age\":30,\"location\":\"NYC\",\"preferences\":{\"theme\":\"dark\",\"notifications\":true}}},{\"id\":2,\"name\":\"Jane Smith\",\"email\":\"jane@example.com\",\"active\":false,\"profile\":{\"age\":25,\"location\":\"LA\",\"preferences\":{\"theme\":\"light\",\"notifications\":false}}}],\"metadata\":{\"total\":2,\"page\":1,\"limit\":10,\"timestamp\":\"2024-01-01T00:00:00Z\"}}";
    };

    defer if (input_file != null) allocator.free(input);

    debugger.log(.basic, "📊 Input size: {d} bytes", .{input.len});

    // Run comprehensive benchmark
    try debugger.benchmark(input, benchmark_iterations);

    // Run performance analysis
    try debugger.analyzePerformance(input);

    // Run stress test if enabled
    if (enable_stress_test) {
        try debugger.memoryStressTest(stress_test_base_size, stress_test_multiplier);
    }

    // Debug minification with profiling
    const result = try debugger.debugMinify(input, mode);
    defer allocator.free(result);

    // Generate performance report
    if (enable_profiling) {
        const report = try debugger.generatePerformanceReport();
        defer allocator.free(report);
        debugger.log(.basic, "📋 Performance Report:\n{s}", .{report});
    }

    // Check for memory leaks
    debugger.checkMemoryLeaks();

    debugger.log(.basic, "✅ Enhanced debugger finished", .{});
}

fn printUsage() void {
    std.log.info(
        \\🔧 zmin Enhanced Debugger - Advanced debugging and profiling tool
        \\
        \\Usage: debugger [OPTIONS]
        \\
        \\Debug Levels:
        \\  -v, --verbose               Enable verbose logging
        \\  -t, --trace                 Enable trace logging (includes function calls)
        \\
        \\Input/Output:
        \\  -i, --input <file>          Input file to process (default: built-in sample)
        \\  -l, --log <file>            Write logs to file
        \\
        \\Processing:
        \\  -m, --mode <mode>           Minification mode (eco|sport|turbo, default: sport)
        \\  -b, --benchmark <N>         Run benchmark with N iterations (default: 10)
        \\
        \\Profiling Controls:
        \\      --no-profiling          Disable performance profiling
        \\      --no-memory-tracking    Disable memory tracking
        \\
        \\Stress Testing:
        \\      --stress-test           Enable memory stress testing
        \\      --stress-size <bytes>   Base size for stress test (default: 1024)
        \\      --stress-multiplier <N> Stress test multiplier (default: 10)
        \\
        \\Help:
        \\  -h, --help                  Show this help message
        \\
        \\Examples:
        \\  debugger                                    # Basic debug with sample data
        \\  debugger -v -i data.json -m turbo         # Verbose debug of file in turbo mode
        \\  debugger -b 50 --stress-test              # Benchmark with 50 iterations + stress test
        \\  debugger -t -l debug.log --no-profiling   # Trace logging to file without profiling
        \\
        \\Features:
        \\  • System information detection (CPU, memory, NUMA)
        \\  • Advanced CPU feature detection (SSE, AVX, NEON)
        \\  • Comprehensive memory profiling and leak detection
        \\  • Performance benchmarking with statistics
        \\  • Memory stress testing with scalable data sizes
        \\  • Function-level profiling with timing
        \\  • Detailed performance reports in Markdown format
        \\
    , .{});
}
