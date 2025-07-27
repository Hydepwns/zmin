const std = @import("std");
const zmin = @import("zmin_lib");
const builtin = @import("builtin");
const errors = @import("common/errors.zig");
const DevToolError = errors.DevToolError;
const ErrorReporter = errors.ErrorReporter;

// System statistics structure
const SystemStats = struct {
    cpu_usage: f64,
    memory_usage: usize,
    memory_total: usize,
    uptime: u64,
    requests_count: u32,
    active_connections: u32,
    average_response_time: f64,
};

// Performance metrics
const PerformanceMetrics = struct {
    minify_count: u32,
    benchmark_count: u32,
    total_bytes_processed: usize,
    average_minify_time: f64,
    cpu_features: []const u8,
    numa_nodes: u32,
};

const Server = struct {
    allocator: std.mem.Allocator,
    port: u16,
    address: std.net.Address,
    server: std.net.Server,
    start_time: i64,
    stats: SystemStats,
    metrics: PerformanceMetrics,
    mutex: std.Thread.Mutex,
    reporter: ErrorReporter,
    file_ops: errors.FileOps,
    process_ops: errors.ProcessOps,

    pub fn init(allocator: std.mem.Allocator, port: u16) !Server {
        const address = std.net.Address.parseIp("127.0.0.1", port) catch |err| {
            switch (err) {
                error.InvalidIPAddressFormat => return DevToolError.InvalidConfiguration,
            }
        };
        const server = address.listen(.{}) catch |err| {
            switch (err) {
                error.AddressInUse => return DevToolError.BindFailed,
                error.PermissionDenied => return DevToolError.PermissionDenied,
                else => return DevToolError.BindFailed,
            }
        };

        var reporter = ErrorReporter.init(allocator, "dev-server");
        const file_ops = errors.FileOps{ .reporter = &reporter };
        const process_ops = errors.ProcessOps{ .reporter = &reporter };

        // Detect CPU features
        const cpu_features = try detectCpuFeatures(allocator);
        
        // Detect NUMA topology
        const numa_nodes = detectNumaNodes();

        // Get total system memory
        const total_memory = getTotalMemory();

        return Server{
            .allocator = allocator,
            .port = port,
            .address = address,
            .server = server,
            .start_time = std.time.timestamp(),
            .stats = SystemStats{
                .cpu_usage = 0.0,
                .memory_usage = 0,
                .memory_total = total_memory,
                .uptime = 0,
                .requests_count = 0,
                .active_connections = 0,
                .average_response_time = 0.0,
            },
            .metrics = PerformanceMetrics{
                .minify_count = 0,
                .benchmark_count = 0,
                .total_bytes_processed = 0,
                .average_minify_time = 0.0,
                .cpu_features = cpu_features,
                .numa_nodes = numa_nodes,
            },
            .mutex = std.Thread.Mutex{},
            .reporter = reporter,
            .file_ops = file_ops,
            .process_ops = process_ops,
        };
    }

    pub fn deinit(self: *Server) void {
        self.server.deinit();
    }

    pub fn run(self: *Server) !void {
        std.log.info("Development server starting on http://127.0.0.1:{d}", .{self.port});
        std.log.info("Press Ctrl+C to stop", .{});

        while (true) {
            const connection = self.server.accept() catch |err| {
                self.reporter.report(err, errors.context("dev-server", "accepting connection"));
                continue; // Continue serving other connections
            };
            defer connection.stream.close();

            self.handleRequest(connection) catch |err| {
                self.reporter.report(err, errors.context("dev-server", "handling HTTP request"));
                // Continue serving other requests
            };
        }
    }

    fn handleRequest(self: *Server, connection: std.net.Server.Connection) !void {
        var buffer: [4096]u8 = undefined;
        const bytes_read = connection.stream.reader().read(&buffer) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "reading HTTP request"));
            return DevToolError.ConnectionFailed;
        };
        const request = buffer[0..bytes_read];

        // Parse HTTP request
        var lines = std.mem.splitSequence(u8, request, "\r\n");
        const request_line = lines.next() orelse {
            self.reporter.report(DevToolError.InvalidRequest, errors.contextWithDetails(
                "dev-server", "parsing HTTP request", "missing request line"
            ));
            return DevToolError.InvalidRequest;
        };

        var parts = std.mem.splitSequence(u8, request_line, " ");
        _ = parts.next() orelse {
            self.reporter.report(DevToolError.InvalidRequest, errors.contextWithDetails(
                "dev-server", "parsing HTTP request", "missing HTTP method"
            ));
            return DevToolError.InvalidRequest;
        }; // method
        const path = parts.next() orelse {
            self.reporter.report(DevToolError.InvalidRequest, errors.contextWithDetails(
                "dev-server", "parsing HTTP request", "missing request path"
            ));
            return DevToolError.InvalidRequest;
        };

        // Track request start time
        const request_start = std.time.nanoTimestamp();
        
        // Handle different routes
        if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html")) {
            try self.serveIndex(connection);
        } else if (std.mem.startsWith(u8, path, "/api/minify")) {
            try self.handleMinifyApi(connection, request);
        } else if (std.mem.startsWith(u8, path, "/api/benchmark")) {
            try self.handleBenchmarkApi(connection, request);
        } else if (std.mem.startsWith(u8, path, "/api/stats")) {
            try self.handleStatsApi(connection);
        } else if (std.mem.startsWith(u8, path, "/api/metrics")) {
            try self.handleMetricsApi(connection);
        } else if (std.mem.startsWith(u8, path, "/api/system")) {
            try self.handleSystemApi(connection);
        } else if (std.mem.startsWith(u8, path, "/api/memory")) {
            try self.handleMemoryApi(connection);
        } else if (std.mem.startsWith(u8, path, "/static/")) {
            try self.serveStatic(connection, path);
        } else {
            try self.serve404(connection);
        }

        // Update request statistics
        const request_duration = @as(f64, @floatFromInt(std.time.nanoTimestamp() - request_start)) / 1_000_000.0;
        self.updateRequestStats(request_duration);
    }

    fn serveIndex(self: *Server, connection: std.net.Server.Connection) !void {
        const html = @embedFile("dev_server/index.html");
        const response =
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/html\r\n" ++
            "Content-Length: " ++ std.fmt.comptimePrint("{d}", .{html.len}) ++ "\r\n" ++
            "\r\n";

        connection.stream.writer().writeAll(response) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "sending index.html response"));
            return DevToolError.ConnectionFailed;
        };
        connection.stream.writer().writeAll(html) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "sending index.html content"));
            return DevToolError.ConnectionFailed;
        };
    }

    fn serveStatic(self: *Server, connection: std.net.Server.Connection, path: []const u8) !void {
        const file_path = path[8..]; // Remove "/static/"

        if (std.mem.eql(u8, file_path, "style.css")) {
            const css = @embedFile("dev_server/style.css");
            const response =
                "HTTP/1.1 200 OK\r\n" ++
                "Content-Type: text/css\r\n" ++
                "Content-Length: " ++ std.fmt.comptimePrint("{d}", .{css.len}) ++ "\r\n" ++
                "\r\n";

            connection.stream.writer().writeAll(response) catch |err| {
                self.reporter.report(err, errors.context("dev-server", "sending CSS response"));
                return DevToolError.ConnectionFailed;
            };
            connection.stream.writer().writeAll(css) catch |err| {
                self.reporter.report(err, errors.context("dev-server", "sending CSS content"));
                return DevToolError.ConnectionFailed;
            };
        } else if (std.mem.eql(u8, file_path, "script.js")) {
            const js = @embedFile("dev_server/script.js");
            const response =
                "HTTP/1.1 200 OK\r\n" ++
                "Content-Type: application/javascript\r\n" ++
                "Content-Length: " ++ std.fmt.comptimePrint("{d}", .{js.len}) ++ "\r\n" ++
                "\r\n";

            connection.stream.writer().writeAll(response) catch |err| {
                self.reporter.report(err, errors.context("dev-server", "sending JS response"));
                return DevToolError.ConnectionFailed;
            };
            connection.stream.writer().writeAll(js) catch |err| {
                self.reporter.report(err, errors.context("dev-server", "sending JS content"));
                return DevToolError.ConnectionFailed;
            };
        } else {
            try self.serve404(connection);
        }
    }

    fn handleMinifyApi(self: *Server, connection: std.net.Server.Connection, request: []const u8) !void {
        // Parse JSON request body
        const body_start = std.mem.indexOf(u8, request, "\r\n\r\n") orelse {
            self.reporter.report(DevToolError.InvalidRequest, errors.contextWithDetails(
                "dev-server", "parsing minify API request", "missing request body"
            ));
            return DevToolError.InvalidRequest;
        };
        const body = request[body_start + 4 ..];

        // Simple JSON parsing for demo
        const input_start = std.mem.indexOf(u8, body, "\"input\":\"") orelse {
            self.reporter.report(DevToolError.InvalidRequest, errors.contextWithDetails(
                "dev-server", "parsing minify API request", "missing 'input' field"
            ));
            return DevToolError.InvalidRequest;
        };
        const input_end = std.mem.indexOfPos(u8, body, input_start + 9, "\"") orelse {
            self.reporter.report(DevToolError.InvalidRequest, errors.contextWithDetails(
                "dev-server", "parsing minify API request", "malformed 'input' field"
            ));
            return DevToolError.InvalidRequest;
        };
        const input = body[input_start + 9 .. input_end];

        const mode_start = std.mem.indexOf(u8, body, "\"mode\":\"") orelse {
            self.reporter.report(DevToolError.InvalidRequest, errors.contextWithDetails(
                "dev-server", "parsing minify API request", "missing 'mode' field"
            ));
            return DevToolError.InvalidRequest;
        };
        const mode_end = std.mem.indexOfPos(u8, body, mode_start + 8, "\"") orelse {
            self.reporter.report(DevToolError.InvalidRequest, errors.contextWithDetails(
                "dev-server", "parsing minify API request", "malformed 'mode' field"
            ));
            return DevToolError.InvalidRequest;
        };
        const mode_str = body[mode_start + 8 .. mode_end];

        // Minify the input
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const mode = if (std.mem.eql(u8, mode_str, "eco"))
            zmin.ProcessingMode.eco
        else if (std.mem.eql(u8, mode_str, "sport"))
            zmin.ProcessingMode.sport
        else
            zmin.ProcessingMode.turbo;

        var timer = std.time.Timer.start() catch |err| {
            self.reporter.report(err, errors.context("dev-server", "starting minify timer"));
            return DevToolError.InternalError;
        };
        const result = zmin.minify(arena.allocator(), input, mode) catch |err| {
            self.reporter.report(err, errors.contextWithDetails(
                "dev-server", "minifying JSON", "minification process failed"
            ));
            return DevToolError.InternalError;
        };
        const elapsed_ns = timer.read();
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

        // Update metrics
        self.updateMinifyStats(elapsed_ms, input.len);

        // Create JSON response
        const response_json = std.fmt.allocPrint(arena.allocator(), "{{\"output\":\"{s}\",\"original_size\":{d},\"minified_size\":{d},\"compression_ratio\":{d:.2}}}", .{
            std.fmt.fmtSliceEscapeLower(result),
            input.len,
            result.len,
            @as(f64, @floatFromInt(input.len)) / @as(f64, @floatFromInt(result.len)),
        }) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "formatting minify response JSON"));
            return DevToolError.OutOfMemory;
        };

        const response = std.fmt.allocPrint(self.allocator,
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: application/json\r\n" ++
            "Access-Control-Allow-Origin: *\r\n" ++
            "Content-Length: {d}\r\n" ++
            "\r\n", .{response_json.len}) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "formatting HTTP response"));
            return DevToolError.OutOfMemory;
        };
        defer self.allocator.free(response);

        connection.stream.writer().writeAll(response) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "sending HTTP response headers"));
            return DevToolError.ConnectionFailed;
        };
        connection.stream.writer().writeAll(response_json) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "sending HTTP response body"));
            return DevToolError.ConnectionFailed;
        };
    }

    fn handleBenchmarkApi(self: *Server, connection: std.net.Server.Connection, request: []const u8) !void {
        // Parse JSON request body
        const body_start = std.mem.indexOf(u8, request, "\r\n\r\n") orelse {
            self.reporter.report(DevToolError.InvalidRequest, errors.contextWithDetails(
                "dev-server", "parsing benchmark API request", "missing request body"
            ));
            return DevToolError.InvalidRequest;
        };
        const body = request[body_start + 4 ..];

        const input_start = std.mem.indexOf(u8, body, "\"input\":\"") orelse {
            self.reporter.report(DevToolError.InvalidRequest, errors.contextWithDetails(
                "dev-server", "parsing benchmark API request", "missing 'input' field"
            ));
            return DevToolError.InvalidRequest;
        };
        const input_end = std.mem.indexOfPos(u8, body, input_start + 9, "\"") orelse {
            self.reporter.report(DevToolError.InvalidRequest, errors.contextWithDetails(
                "dev-server", "parsing benchmark API request", "malformed 'input' field"
            ));
            return DevToolError.InvalidRequest;
        };
        const input = body[input_start + 9 .. input_end];

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        // Update benchmark count
        self.mutex.lock();
        self.metrics.benchmark_count += 1;
        self.mutex.unlock();

        // Benchmark all modes
        const modes = [_]zmin.ProcessingMode{ .eco, .sport, .turbo };
        var results: [3]struct {
            mode: []const u8,
            time_ns: u64,
            size: usize,
        } = undefined;

        for (modes, 0..) |mode, i| {
            var timer = std.time.Timer.start() catch |err| {
                self.reporter.report(err, errors.context("dev-server", "starting benchmark timer"));
                return DevToolError.InternalError;
            };
            const result = zmin.minify(arena.allocator(), input, mode) catch |err| {
                self.reporter.report(err, errors.contextWithDetails(
                    "dev-server", "benchmarking JSON minification", "minification process failed"
                ));
                return DevToolError.InternalError;
            };
            const elapsed = timer.read();

            results[i] = .{
                .mode = switch (mode) {
                    .eco => "eco",
                    .sport => "sport",
                    .turbo => "turbo",
                },
                .time_ns = elapsed,
                .size = result.len,
            };
        }

        // Create JSON response
        const response_json = std.fmt.allocPrint(arena.allocator(), "{{\"results\":[{{\"mode\":\"{s}\",\"time_ms\":{d:.2},\"size\":{d}}},{{\"mode\":\"{s}\",\"time_ms\":{d:.2},\"size\":{d}}},{{\"mode\":\"{s}\",\"time_ms\":{d:.2},\"size\":{d}}}]}}", .{
            results[0].mode, @as(f64, @floatFromInt(results[0].time_ns)) / 1_000_000.0, results[0].size,
            results[1].mode, @as(f64, @floatFromInt(results[1].time_ns)) / 1_000_000.0, results[1].size,
            results[2].mode, @as(f64, @floatFromInt(results[2].time_ns)) / 1_000_000.0, results[2].size,
        }) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "formatting benchmark response JSON"));
            return DevToolError.OutOfMemory;
        };

        const response = std.fmt.allocPrint(self.allocator,
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: application/json\r\n" ++
            "Access-Control-Allow-Origin: *\r\n" ++
            "Content-Length: {d}\r\n" ++
            "\r\n", .{response_json.len}) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "formatting benchmark HTTP response"));
            return DevToolError.OutOfMemory;
        };
        defer self.allocator.free(response);

        connection.stream.writer().writeAll(response) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "sending benchmark response headers"));
            return DevToolError.ConnectionFailed;
        };
        connection.stream.writer().writeAll(response_json) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "sending benchmark response body"));
            return DevToolError.ConnectionFailed;
        };
    }

    fn serve404(self: *Server, connection: std.net.Server.Connection) !void {
        const html =
            "<html><head><title>404 Not Found</title></head>" ++
            "<body><h1>404 Not Found</h1><p>The requested resource was not found.</p></body></html>";

        const response =
            "HTTP/1.1 404 Not Found\r\n" ++
            "Content-Type: text/html\r\n" ++
            "Content-Length: " ++ std.fmt.comptimePrint("{d}", .{html.len}) ++ "\r\n" ++
            "\r\n";

        connection.stream.writer().writeAll(response) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "sending 404 response"));
            return DevToolError.ConnectionFailed;
        };
        connection.stream.writer().writeAll(html) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "sending 404 content"));
            return DevToolError.ConnectionFailed;
        };
    }

    // New API handlers for enhanced development server
    fn handleStatsApi(self: *Server, connection: std.net.Server.Connection) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Update uptime
        self.stats.uptime = @as(u64, @intCast(std.time.timestamp() - self.start_time));
        
        // Update memory usage
        self.stats.memory_usage = getCurrentMemoryUsage();

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const response_json = try std.fmt.allocPrint(arena.allocator(),
            \\{{"cpu_usage":{d:.1},"memory_usage":{d},"memory_total":{d},"uptime":{d},"requests_count":{d},"active_connections":{d},"average_response_time":{d:.2}}}
        , .{
            self.stats.cpu_usage,
            self.stats.memory_usage,
            self.stats.memory_total,
            self.stats.uptime,
            self.stats.requests_count,
            self.stats.active_connections,
            self.stats.average_response_time,
        });

        try self.sendJsonResponse(connection, response_json);
    }

    fn handleMetricsApi(self: *Server, connection: std.net.Server.Connection) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const response_json = try std.fmt.allocPrint(arena.allocator(),
            \\{{"minify_count":{d},"benchmark_count":{d},"total_bytes_processed":{d},"average_minify_time":{d:.2},"cpu_features":"{s}","numa_nodes":{d}}}
        , .{
            self.metrics.minify_count,
            self.metrics.benchmark_count,
            self.metrics.total_bytes_processed,
            self.metrics.average_minify_time,
            self.metrics.cpu_features,
            self.metrics.numa_nodes,
        });

        try self.sendJsonResponse(connection, response_json);
    }

    fn handleSystemApi(self: *Server, connection: std.net.Server.Connection) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const system_info = try getSystemInfo(arena.allocator());
        
        const response_json = try std.fmt.allocPrint(arena.allocator(),
            \\{{"os":"{s}","arch":"{s}","cpu_count":{d},"zig_version":"{s}","build_mode":"{s}","endian":"{s}"}}
        , .{
            system_info.os,
            system_info.arch,
            system_info.cpu_count,
            system_info.zig_version,
            system_info.build_mode,
            system_info.endian,
        });

        try self.sendJsonResponse(connection, response_json);
    }

    fn handleMemoryApi(self: *Server, connection: std.net.Server.Connection) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const memory_info = getDetailedMemoryInfo();
        
        const response_json = try std.fmt.allocPrint(arena.allocator(),
            \\{{"heap_allocated":{d},"heap_available":{d},"rss":{d},"virtual":{d},"gc_count":{d},"page_faults":{d}}}
        , .{
            memory_info.heap_allocated,
            memory_info.heap_available,
            memory_info.rss,
            memory_info.virtual,
            memory_info.gc_count,
            memory_info.page_faults,
        });

        try self.sendJsonResponse(connection, response_json);
    }

    fn sendJsonResponse(self: *Server, connection: std.net.Server.Connection, json: []const u8) !void {
        const response = std.fmt.allocPrint(self.allocator,
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: application/json\r\n" ++
            "Access-Control-Allow-Origin: *\r\n" ++
            "Content-Length: {d}\r\n" ++
            "\r\n", .{json.len}) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "formatting JSON response"));
            return DevToolError.OutOfMemory;
        };
        defer self.allocator.free(response);

        connection.stream.writer().writeAll(response) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "sending JSON response headers"));
            return DevToolError.ConnectionFailed;
        };
        connection.stream.writer().writeAll(json) catch |err| {
            self.reporter.report(err, errors.context("dev-server", "sending JSON response body"));
            return DevToolError.ConnectionFailed;
        };
    }

    fn updateRequestStats(self: *Server, duration_ms: f64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.stats.requests_count += 1;
        
        // Calculate rolling average response time
        const weight = 0.1; // Weight for new sample
        self.stats.average_response_time = (1.0 - weight) * self.stats.average_response_time + weight * duration_ms;
    }

    fn updateMinifyStats(self: *Server, duration_ms: f64, bytes_processed: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.metrics.minify_count += 1;
        self.metrics.total_bytes_processed += bytes_processed;
        
        // Calculate rolling average minify time
        const weight = 0.1;
        self.metrics.average_minify_time = (1.0 - weight) * self.metrics.average_minify_time + weight * duration_ms;
    }
};

// System detection functions
fn detectCpuFeatures(allocator: std.mem.Allocator) ![]const u8 {
    var features = std.ArrayList(u8).init(allocator);
    defer features.deinit();

    const writer = features.writer();
    
    // Detect common CPU features
    if (std.Target.x86.featureSetHas(builtin.cpu.features, .sse)) {
        try writer.writeAll("SSE ");
    }
    if (std.Target.x86.featureSetHas(builtin.cpu.features, .sse2)) {
        try writer.writeAll("SSE2 ");
    }
    if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx)) {
        try writer.writeAll("AVX ");
    }
    if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx2)) {
        try writer.writeAll("AVX2 ");
    }
    if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx512f)) {
        try writer.writeAll("AVX512 ");
    }

    return try allocator.dupe(u8, features.items);
}

fn detectNumaNodes() u32 {
    // Try to detect NUMA nodes (simplified detection)
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
    // Try to read from /proc/meminfo on Linux
    const meminfo = std.fs.cwd().readFileAlloc(std.heap.page_allocator, "/proc/meminfo", 4096) catch return 1024 * 1024 * 1024; // 1GB default
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
                const kb_value = std.fmt.parseInt(usize, kb, 10) catch return 1024 * 1024 * 1024;
                return kb_value * 1024; // Convert KB to bytes
            }
        }
    }
    
    return 1024 * 1024 * 1024; // 1GB default
}

fn getCurrentMemoryUsage() usize {
    // Simplified memory usage detection
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

const SystemInfo = struct {
    os: []const u8,
    arch: []const u8,
    cpu_count: u32,
    zig_version: []const u8,
    build_mode: []const u8,
    endian: []const u8,
};

fn getSystemInfo(allocator: std.mem.Allocator) !SystemInfo {
    const cpu_count = std.Thread.getCpuCount() catch 1;
    
    return SystemInfo{
        .os = @tagName(builtin.os.tag),
        .arch = @tagName(builtin.cpu.arch),
        .cpu_count = @intCast(cpu_count),
        .zig_version = try allocator.dupe(u8, builtin.zig_version_string),
        .build_mode = @tagName(builtin.mode),
        .endian = @tagName(builtin.cpu.arch.endian()),
    };
}

const MemoryInfo = struct {
    heap_allocated: usize,
    heap_available: usize,
    rss: usize,
    virtual: usize,
    gc_count: u32,
    page_faults: u32,
};

fn getDetailedMemoryInfo() MemoryInfo {
    // Simplified memory info - in a real implementation, you'd use platform-specific APIs
    return MemoryInfo{
        .heap_allocated = getCurrentMemoryUsage(),
        .heap_available = getTotalMemory() - getCurrentMemoryUsage(),
        .rss = getCurrentMemoryUsage(),
        .virtual = getCurrentMemoryUsage() * 2, // Rough estimate
        .gc_count = 0, // Zig doesn't have GC
        .page_faults = 0, // Would need platform-specific implementation
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const port: u16 = if (args.len > 1)
        try std.fmt.parseInt(u16, args[1], 10)
    else
        8080;

    var server = try Server.init(allocator, port);
    defer server.deinit();

    try server.run();
}
