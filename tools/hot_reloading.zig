const std = @import("std");
const zmin = @import("zmin_lib");
const builtin = @import("builtin");

// File change event
const FileEvent = struct {
    path: []const u8,
    event_type: EventType,
    timestamp: i64,
};

const EventType = enum {
    created,
    modified,
    deleted,
    moved,
};

// Build statistics
const BuildStats = struct {
    total_builds: u32,
    successful_builds: u32,
    failed_builds: u32,
    average_build_time: f64,
    last_build_duration: u64,
    fastest_build: u64,
    slowest_build: u64,
};

// Hot reloader configuration
const Config = struct {
    watch_extensions: []const []const u8,
    ignore_patterns: []const []const u8,
    debounce_ms: u64,
    max_parallel_builds: u32,
    enable_notifications: bool,
    clear_console: bool,
    verbose: bool,
};

const HotReloader = struct {
    allocator: std.mem.Allocator,
    watch_paths: std.ArrayList([]const u8),
    build_command: []const u8,
    last_build_time: i64,
    is_building: bool,
    config: Config,
    stats: BuildStats,
    file_hashes: std.HashMap([]const u8, u64, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    event_queue: std.ArrayList(FileEvent),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) HotReloader {
        const default_extensions = [_][]const u8{ ".zig", ".c", ".h", ".cpp", ".hpp", ".js", ".ts", ".html", ".css", ".json", ".toml", ".yaml", ".yml" };
        const default_ignore = [_][]const u8{ ".git", ".zig-cache", "zig-out", "node_modules", ".vscode", ".idea", "target", "build" };
        
        return HotReloader{
            .allocator = allocator,
            .watch_paths = std.ArrayList([]const u8).init(allocator),
            .build_command = "zig build",
            .last_build_time = 0,
            .is_building = false,
            .config = Config{
                .watch_extensions = &default_extensions,
                .ignore_patterns = &default_ignore,
                .debounce_ms = 200,
                .max_parallel_builds = 1,
                .enable_notifications = true,
                .clear_console = true,
                .verbose = false,
            },
            .stats = BuildStats{
                .total_builds = 0,
                .successful_builds = 0,
                .failed_builds = 0,
                .average_build_time = 0.0,
                .last_build_duration = 0,
                .fastest_build = std.math.maxInt(u64),
                .slowest_build = 0,
            },
            .file_hashes = std.HashMap([]const u8, u64, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .event_queue = std.ArrayList(FileEvent).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *HotReloader) void {
        self.watch_paths.deinit();
        self.file_hashes.deinit();
        self.event_queue.deinit();
    }

    pub fn addWatchPath(self: *HotReloader, path: []const u8) !void {
        try self.watch_paths.append(path);
    }

    pub fn setBuildCommand(self: *HotReloader, command: []const u8) void {
        self.build_command = command;
    }

    pub fn setVerbose(self: *HotReloader, verbose: bool) void {
        self.config.verbose = verbose;
    }

    pub fn setDebounceMs(self: *HotReloader, ms: u64) void {
        self.config.debounce_ms = ms;
    }

    pub fn setClearConsole(self: *HotReloader, clear: bool) void {
        self.config.clear_console = clear;
    }

    pub fn run(self: *HotReloader) !void {
        std.log.info("🔥 Hot reloader starting...", .{});
        std.log.info("📁 Watching paths:", .{});
        for (self.watch_paths.items) |path| {
            std.log.info("  - {s}", .{path});
        }
        std.log.info("🔨 Build command: {s}", .{self.build_command});
        std.log.info("⏱️  Debounce time: {d}ms", .{self.config.debounce_ms});
        std.log.info("📂 Watching extensions: {s}", .{self.config.watch_extensions});
        std.log.info("🚫 Ignoring patterns: {s}", .{self.config.ignore_patterns});
        std.log.info("Press Ctrl+C to stop", .{});

        // Build initial file hash table
        try self.buildFileHashTable();

        // Initial build
        try self.triggerBuild();

        // Start event processing thread
        const event_thread = try std.Thread.spawn(.{}, processEvents, .{self});
        defer event_thread.join();

        // Watch for changes
        try self.watchFilesAdvanced();
    }

    fn watchFiles(self: *HotReloader) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        // Get all files to watch
        var all_files = std.ArrayList([]const u8).init(allocator);
        defer all_files.deinit();

        for (self.watch_paths.items) |path| {
            try self.collectFiles(path, &all_files);
        }

        std.log.info("Watching {d} files for changes", .{all_files.items.len});

        // Monitor files for changes
        while (true) {
            var changed = false;

            for (all_files.items) |file_path| {
                const file_info = std.fs.cwd().statFile(file_path) catch continue;

                if (file_info.mtime > self.last_build_time) {
                    std.log.info("File changed: {s}", .{file_path});
                    changed = true;
                    break;
                }
            }

            if (changed and !self.is_building) {
                try self.triggerBuild();
            }

            // Sleep for a short time
            std.time.sleep(100 * std.time.ns_per_ms);
        }
    }

    fn collectFiles(self: *HotReloader, path: []const u8, files: *std.ArrayList([]const u8)) !void {
        const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
            if (err == error.NotDir) {
                // It's a file, add it
                try files.append(path);
                return;
            }
            return err;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next()) |entry| {
            entry catch continue;
            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, entry.name });

            if (entry.kind == .directory) {
                // Skip common directories that don't need watching
                if (std.mem.eql(u8, entry.name, ".git") or
                    std.mem.eql(u8, entry.name, ".zig-cache") or
                    std.mem.eql(u8, entry.name, "zig-out") or
                    std.mem.eql(u8, entry.name, "node_modules"))
                {
                    continue;
                }
                try self.collectFiles(full_path, files);
            } else {
                // Only watch relevant file types
                if (self.shouldWatchFile(entry.name)) {
                    try files.append(full_path);
                }
            }
        }
    }

    fn shouldWatchFile(self: *HotReloader, filename: []const u8) bool {
        _ = self;
        const extensions = [_][]const u8{ ".zig", ".c", ".h", ".cpp", ".hpp", ".js", ".ts", ".html", ".css" };

        for (extensions) |ext| {
            if (std.mem.endsWith(u8, filename, ext)) {
                return true;
            }
        }

        // Also watch common config files
        const config_files = [_][]const u8{ "build.zig", "build.zig.zon", "package.json", "Cargo.toml" };
        for (config_files) |config| {
            if (std.mem.eql(u8, filename, config)) {
                return true;
            }
        }

        return false;
    }

    fn triggerBuild(self: *HotReloader) !void {
        if (self.is_building) {
            std.log.info("Build already in progress, skipping...", .{});
            return;
        }

        self.is_building = true;
        defer self.is_building = false;

        std.log.info("Triggering build...", .{});
        const start_time = std.time.milliTimestamp();

        // Run build command
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "sh", "-c", self.build_command },
        }) catch |err| {
            std.log.err("Failed to execute build command: {}", .{err});
            return;
        };

        const end_time = std.time.milliTimestamp();
        const duration = end_time - start_time;

        if (result.term.Exited == 0) {
            std.log.info("Build completed successfully in {d}ms", .{duration});
            self.last_build_time = std.time.milliTimestamp();
        } else {
            std.log.err("Build failed after {d}ms", .{duration});
            if (result.stderr.len > 0) {
                std.log.err("Build error: {s}", .{result.stderr});
            }
        }

        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);
    }

    // Enhanced file watching with hash-based change detection
    fn buildFileHashTable(self: *HotReloader) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var all_files = std.ArrayList([]const u8).init(arena.allocator());
        defer all_files.deinit();

        for (self.watch_paths.items) |path| {
            try self.collectFilesAdvanced(path, &all_files);
        }

        if (self.config.verbose) {
            std.log.info("Building hash table for {d} files", .{all_files.items.len});
        }

        for (all_files.items) |file_path| {
            const hash = try self.calculateFileHash(file_path);
            try self.file_hashes.put(try self.allocator.dupe(u8, file_path), hash);
        }
    }

    fn watchFilesAdvanced(self: *HotReloader) !void {
        while (true) {
            var changes_detected = false;
            
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();

            var current_files = std.ArrayList([]const u8).init(arena.allocator());
            defer current_files.deinit();

            // Collect all current files
            for (self.watch_paths.items) |path| {
                try self.collectFilesAdvanced(path, &current_files);
            }

            // Check for changes using hashes
            for (current_files.items) |file_path| {
                const current_hash = self.calculateFileHash(file_path) catch continue;
                
                if (self.file_hashes.get(file_path)) |stored_hash| {
                    if (current_hash != stored_hash) {
                        // File modified
                        try self.queueEvent(FileEvent{
                            .path = try self.allocator.dupe(u8, file_path),
                            .event_type = .modified,
                            .timestamp = std.time.milliTimestamp(),
                        });
                        try self.file_hashes.put(try self.allocator.dupe(u8, file_path), current_hash);
                        changes_detected = true;
                        
                        if (self.config.verbose) {
                            std.log.info("📝 Modified: {s}", .{file_path});
                        }
                    }
                } else {
                    // New file
                    try self.queueEvent(FileEvent{
                        .path = try self.allocator.dupe(u8, file_path),
                        .event_type = .created,
                        .timestamp = std.time.milliTimestamp(),
                    });
                    try self.file_hashes.put(try self.allocator.dupe(u8, file_path), current_hash);
                    changes_detected = true;
                    
                    if (self.config.verbose) {
                        std.log.info("✨ Created: {s}", .{file_path});
                    }
                }
            }

            // Check for deleted files
            var hash_iterator = self.file_hashes.iterator();
            while (hash_iterator.next()) |entry| {
                var found = false;
                for (current_files.items) |file_path| {
                    if (std.mem.eql(u8, entry.key_ptr.*, file_path)) {
                        found = true;
                        break;
                    }
                }
                
                if (!found) {
                    try self.queueEvent(FileEvent{
                        .path = try self.allocator.dupe(u8, entry.key_ptr.*),
                        .event_type = .deleted,
                        .timestamp = std.time.milliTimestamp(),
                    });
                    changes_detected = true;
                    
                    if (self.config.verbose) {
                        std.log.info("🗑️  Deleted: {s}", .{entry.key_ptr.*});
                    }
                }
            }

            if (changes_detected) {
                self.printStats();
            }

            // Sleep for polling interval
            std.time.sleep(self.config.debounce_ms * std.time.ns_per_ms / 2);
        }
    }

    fn collectFilesAdvanced(self: *HotReloader, path: []const u8, files: *std.ArrayList([]const u8)) !void {
        const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
            if (err == error.NotDir) {
                // It's a file, check if we should watch it
                if (self.shouldWatchFileAdvanced(path)) {
                    try files.append(path);
                }
                return;
            }
            return err;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next()) |entry| {
            entry catch continue;
            
            // Check ignore patterns
            if (self.shouldIgnore(entry.name)) {
                continue;
            }

            const full_path = try std.fmt.allocPrint(files.allocator, "{s}/{s}", .{ path, entry.name });

            if (entry.kind == .directory) {
                try self.collectFilesAdvanced(full_path, files);
            } else {
                if (self.shouldWatchFileAdvanced(entry.name)) {
                    try files.append(full_path);
                }
            }
        }
    }

    fn shouldWatchFileAdvanced(self: *HotReloader, filename: []const u8) bool {
        for (self.config.watch_extensions) |ext| {
            if (std.mem.endsWith(u8, filename, ext)) {
                return true;
            }
        }

        // Check common config files
        const config_files = [_][]const u8{ "build.zig", "build.zig.zon", "package.json", "Cargo.toml", "Makefile" };
        for (config_files) |config| {
            if (std.mem.eql(u8, filename, config)) {
                return true;
            }
        }

        return false;
    }

    fn shouldIgnore(self: *HotReloader, name: []const u8) bool {
        for (self.config.ignore_patterns) |pattern| {
            if (std.mem.indexOf(u8, name, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    fn calculateFileHash(self: *HotReloader, file_path: []const u8) !u64 {
        _ = self;
        const file = std.fs.cwd().openFile(file_path, .{}) catch return 0;
        defer file.close();

        const contents = file.readToEndAlloc(std.heap.page_allocator, 1024 * 1024) catch return 0;
        defer std.heap.page_allocator.free(contents);

        return std.hash_map.hashString(contents);
    }

    fn queueEvent(self: *HotReloader, event: FileEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.event_queue.append(event);
    }

    fn printStats(self: *HotReloader) void {
        if (!self.config.verbose) return;

        const success_rate = if (self.stats.total_builds > 0) 
            (@as(f64, @floatFromInt(self.stats.successful_builds)) / @as(f64, @floatFromInt(self.stats.total_builds))) * 100.0 
        else 
            0.0;

        std.log.info("📊 Stats: {d} builds, {d:.1}% success, avg {d:.1}ms", .{
            self.stats.total_builds,
            success_rate,
            self.stats.average_build_time
        });
    }

    fn clearConsole(self: *HotReloader) void {
        if (self.config.clear_console) {
            _ = std.io.getStdOut().write("\x1B[2J\x1B[H") catch {};
        }
    }

    fn sendNotification(self: *HotReloader, message: []const u8) void {
        if (!self.config.enable_notifications) return;
        
        // On Linux, try to use notify-send
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "notify-send", "Hot Reloader", message },
        }) catch return;
        
        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);
    }
};

// Event processing function (runs in separate thread)
fn processEvents(hot_reloader: *HotReloader) void {
    var last_build_time: i64 = 0;
    
    while (true) {
        std.time.sleep(hot_reloader.config.debounce_ms * std.time.ns_per_ms);
        
        hot_reloader.mutex.lock();
        const has_events = hot_reloader.event_queue.items.len > 0;
        const current_time = std.time.milliTimestamp();
        hot_reloader.mutex.unlock();

        if (has_events and (current_time - last_build_time) >= hot_reloader.config.debounce_ms) {
            hot_reloader.mutex.lock();
            hot_reloader.event_queue.clearRetainingCapacity();
            hot_reloader.mutex.unlock();
            
            if (!hot_reloader.is_building) {
                hot_reloader.triggerBuild() catch |err| {
                    std.log.err("Build trigger failed: {}", .{err});
                };
                last_build_time = current_time;
            }
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var hot_reloader = HotReloader.init(allocator);
    defer hot_reloader.deinit();

    // Parse command line arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--build-command") or std.mem.eql(u8, arg, "-b")) {
            if (i + 1 >= args.len) {
                std.log.err("Missing build command", .{});
                return error.InvalidArguments;
            }
            hot_reloader.setBuildCommand(args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            hot_reloader.setVerbose(true);
        } else if (std.mem.eql(u8, arg, "--debounce") or std.mem.eql(u8, arg, "-d")) {
            if (i + 1 >= args.len) {
                std.log.err("Missing debounce time", .{});
                return error.InvalidArguments;
            }
            const debounce_ms = std.fmt.parseInt(u64, args[i + 1], 10) catch {
                std.log.err("Invalid debounce time: {s}", .{args[i + 1]});
                return error.InvalidArguments;
            };
            hot_reloader.setDebounceMs(debounce_ms);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--no-clear")) {
            hot_reloader.setClearConsole(false);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            std.log.err("Unknown option: {s}", .{arg});
            printHelp();
            return error.InvalidArguments;
        } else {
            // Treat as watch path
            try hot_reloader.addWatchPath(arg);
        }
    }

    // Add default watch paths if none specified
    if (hot_reloader.watch_paths.items.len == 0) {
        try hot_reloader.addWatchPath("src");
        try hot_reloader.addWatchPath("tools");
        try hot_reloader.addWatchPath("examples");
        try hot_reloader.addWatchPath("tests");
    }

    try hot_reloader.run();
}

fn printHelp() void {
    std.log.info(
        \\🔥 Hot Reloader - Advanced file watching and build automation
        \\
        \\Usage: hot_reloading [OPTIONS] [PATHS...]
        \\
        \\Options:
        \\  -b, --build-command <CMD>   Build command to run (default: "zig build")
        \\  -v, --verbose               Enable verbose output with detailed stats
        \\  -d, --debounce <MS>         Debounce time in milliseconds (default: 200)
        \\      --no-clear              Don't clear console between builds
        \\  -h, --help                  Show this help message
        \\
        \\Arguments:
        \\  PATHS...                    Directories or files to watch
        \\                              (default: src, tools, examples, tests)
        \\
        \\Examples:
        \\  hot_reloading                                    # Watch default paths
        \\  hot_reloading -v src tests                      # Watch src and tests with verbose output
        \\  hot_reloading -b "make all" --debounce 500 src  # Custom build command with 500ms debounce
        \\  hot_reloading --no-clear src                    # Don't clear console between builds
        \\
        \\Features:
        \\  • Hash-based change detection for accurate file monitoring
        \\  • Intelligent debouncing to prevent excessive rebuilds
        \\  • Multi-threaded event processing
        \\  • Build statistics and performance monitoring
        \\  • Glob pattern matching and ignore patterns
        \\  • Desktop notifications (Linux)
        \\  • Configurable file type watching
        \\
    );
}
