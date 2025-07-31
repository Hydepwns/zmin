const std = @import("std");

/// Common error set for all dev tools
pub const DevToolError = error{
    // Configuration errors
    InvalidConfiguration,
    ConfigurationNotFound,
    ConfigurationParseError,
    InvalidConfigValue,

    // File system errors
    FileNotFound,
    DirectoryNotFound,
    PermissionDenied,
    FileReadError,
    FileWriteError,

    // Process errors
    ProcessSpawnFailed,
    ProcessExecutionFailed,
    ProcessTimeout,

    // Network errors (for dev server)
    BindFailed,
    ConnectionFailed,
    InvalidRequest,

    // Plugin errors
    PluginLoadFailed,
    PluginNotFound,
    PluginInitFailed,
    InvalidPlugin,

    // Argument errors
    InvalidArguments,
    MissingArgument,
    UnknownCommand,

    // Resource errors
    OutOfMemory,
    ResourceNotAvailable,

    // General errors
    NotImplemented,
    InternalError,
};

/// Error context information
pub const ErrorContext = struct {
    tool_name: []const u8,
    operation: []const u8,
    details: ?[]const u8 = null,
    file_path: ?[]const u8 = null,
    line_number: ?u32 = null,

    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("[{s}] Error in {s}", .{ self.tool_name, self.operation });

        if (self.file_path) |path| {
            try writer.print(" (file: {s}", .{path});
            if (self.line_number) |line| {
                try writer.print(":{d}", .{line});
            }
            try writer.writeAll(")");
        }

        if (self.details) |details| {
            try writer.print(": {s}", .{details});
        }
    }
};

/// Enhanced error reporting
pub const ErrorReporter = struct {
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    verbose: bool = false,

    pub fn init(allocator: std.mem.Allocator, tool_name: []const u8) ErrorReporter {
        return .{
            .allocator = allocator,
            .tool_name = tool_name,
        };
    }

    pub fn setVerbose(self: *ErrorReporter, verbose: bool) void {
        self.verbose = verbose;
    }

    pub fn report(self: *ErrorReporter, err: anyerror, ctx: ErrorContext) void {
        const stderr = std.io.getStdErr().writer();

        // Print error symbol
        stderr.print("❌ ", .{}) catch {};

        // Print context
        stderr.print("{}", .{ctx}) catch {};

        // Print error type
        stderr.print("\n   Error: {s}\n", .{@errorName(err)}) catch {};

        // Print stack trace if verbose
        if (self.verbose) {
            if (@errorReturnTrace()) |trace| {
                stderr.print("\nStack trace:\n", .{}) catch {};
                std.debug.dumpStackTrace(trace.*);
            }
        }

        // Print suggestions based on error type
        self.printSuggestions(err) catch {};
    }

    pub fn reportWithExit(self: *ErrorReporter, err: anyerror, ctx: ErrorContext) noreturn {
        self.report(err, ctx);
        std.process.exit(1);
    }

    fn printSuggestions(self: *ErrorReporter, err: anyerror) !void {
        _ = self;
        const stderr = std.io.getStdErr().writer();

        try stderr.print("\n💡 Suggestion: ", .{});

        switch (err) {
            error.FileNotFound => try stderr.print("Check if the file exists and the path is correct\n", .{}),
            error.PermissionDenied => try stderr.print("Check file permissions or run with appropriate privileges\n", .{}),
            error.InvalidArguments => try stderr.print("Run with --help to see usage information\n", .{}),
            error.ProcessSpawnFailed => try stderr.print("Ensure the command exists and is in your PATH\n", .{}),
            error.BindFailed => try stderr.print("Check if the port is already in use or try a different port\n", .{}),
            error.OutOfMemory => try stderr.print("Try processing smaller files or increase available memory\n", .{}),
            error.ConfigurationNotFound => try stderr.print("Run 'config-manager reset' to create default configuration\n", .{}),
            else => try stderr.print("Check the error details above for more information\n", .{}),
        }
    }
};

/// Result type for operations that can fail with context
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: struct {
            error_value: anyerror,
            context: ErrorContext,
        },

        pub fn unwrap(self: @This()) !T {
            switch (self) {
                .ok => |value| return value,
                .err => |e| return e.error_value,
            }
        }

        pub fn unwrapOr(self: @This(), default: T) T {
            switch (self) {
                .ok => |value| return value,
                .err => return default,
            }
        }

        pub fn isOk(self: @This()) bool {
            return switch (self) {
                .ok => true,
                .err => false,
            };
        }

        pub fn isErr(self: @This()) bool {
            return !self.isOk();
        }
    };
}

/// Helper function to create error context
pub fn context(tool_name: []const u8, operation: []const u8) ErrorContext {
    return .{
        .tool_name = tool_name,
        .operation = operation,
    };
}

/// Helper function to create error context with details
pub fn contextWithDetails(tool_name: []const u8, operation: []const u8, details: []const u8) ErrorContext {
    return .{
        .tool_name = tool_name,
        .operation = operation,
        .details = details,
    };
}

/// Helper function to create error context with file info
pub fn contextWithFile(tool_name: []const u8, operation: []const u8, file_path: []const u8) ErrorContext {
    return .{
        .tool_name = tool_name,
        .operation = operation,
        .file_path = file_path,
    };
}

/// Wrapper for file operations with better error handling
pub const FileOps = struct {
    reporter: *ErrorReporter,

    pub fn readFile(self: FileOps, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        return std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize)) catch |err| {
            self.reporter.report(err, contextWithFile(self.reporter.tool_name, "reading file", path));
            return err;
        };
    }

    pub fn writeFile(self: FileOps, path: []const u8, contents: []const u8) !void {
        std.fs.cwd().writeFile(path, contents) catch |err| {
            self.reporter.report(err, contextWithFile(self.reporter.tool_name, "writing file", path));
            return err;
        };
    }

    pub fn createFile(self: FileOps, path: []const u8) !std.fs.File {
        return std.fs.cwd().createFile(path, .{}) catch |err| {
            self.reporter.report(err, contextWithFile(self.reporter.tool_name, "creating file", path));
            return err;
        };
    }

    pub fn openFile(self: FileOps, path: []const u8) !std.fs.File {
        return std.fs.cwd().openFile(path, .{}) catch |err| {
            self.reporter.report(err, contextWithFile(self.reporter.tool_name, "opening file", path));
            return err;
        };
    }

    pub fn deleteFile(self: FileOps, path: []const u8) !void {
        std.fs.cwd().deleteFile(path) catch |err| {
            if (err != error.FileNotFound) {
                self.reporter.report(err, contextWithFile(self.reporter.tool_name, "deleting file", path));
                return err;
            }
        };
    }
};

/// Process execution with better error handling
pub const ProcessOps = struct {
    reporter: *ErrorReporter,

    pub fn exec(self: ProcessOps, allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
        return std.process.Child.run(.{
            .allocator = allocator,
            .argv = argv,
        }) catch |err| {
            const command = std.mem.join(allocator, " ", argv) catch "unknown command";
            defer allocator.free(command);

            self.reporter.report(err, contextWithDetails(self.reporter.tool_name, "executing process", command));
            return err;
        };
    }
};
