const std = @import("std");
const Allocator = std.mem.Allocator;
const TokenStream = @import("../streaming/parser.zig").TokenStream;
const Token = @import("../streaming/parser.zig").Token;
const TokenType = @import("../streaming/parser.zig").TokenType;

/// Output stream for transformed data
pub const OutputStream = struct {
    const Self = @This();

    /// Output buffer
    buffer: std.ArrayList(u8),

    /// Writer interface
    writer: ?std.io.AnyWriter = null,

    /// Track bytes written for statistics
    bytes_written: usize = 0,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn initWithWriter(allocator: Allocator, writer: std.io.AnyWriter) Self {
        return Self{
            .buffer = std.ArrayList(u8).init(allocator),
            .writer = writer,
            .bytes_written = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn write(self: *Self, data: []const u8) !void {
        if (self.writer) |writer| {
            try writer.writeAll(data);
        } else {
            try self.buffer.appendSlice(data);
        }
        self.bytes_written += data.len;
    }

    pub fn writeToken(self: *Self, token: Token, input_data: []const u8) !void {
        if (token.value) |value| {
            try self.write(value);
        } else if (token.start < token.end and token.end <= input_data.len) {
            try self.write(input_data[token.start..token.end]);
        }
    }

    pub fn getBuffer(self: *Self) []const u8 {
        return self.buffer.items;
    }

    pub fn clear(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }
};

/// Transformation types
pub const TransformationType = enum {
    minify,
    filter_fields,
    validate_schema,
    convert_format,
    custom,
};

/// Minification configuration
pub const MinifyConfig = struct {
    /// Remove all whitespace
    remove_whitespace: bool = true,

    /// Remove comments
    remove_comments: bool = true,

    /// Aggressive minification (remove unnecessary quotes, etc.)
    aggressive: bool = false,
};

/// Field filtering configuration
pub const FilterConfig = struct {
    /// Fields to include (if null, include all)
    include: ?[]const []const u8 = null,

    /// Fields to exclude (if null, exclude none)
    exclude: ?[]const []const u8 = null,

    /// Case sensitive matching
    case_sensitive: bool = true,
};

/// Schema validation configuration
pub const SchemaConfig = struct {
    /// JSON Schema data
    schema: []const u8,

    /// Validation mode
    mode: ValidationMode = .strict,
};

/// Validation modes
pub const ValidationMode = enum {
    strict,
    lenient,
    warning_only,
};

/// Output format configuration
pub const FormatConfig = struct {
    /// Output format
    format: OutputFormat = .json,

    /// Pretty print (for JSON)
    pretty_print: bool = false,

    /// Indentation size (for pretty printing)
    indent_size: usize = 2,
};

/// Output formats
pub const OutputFormat = enum {
    json,
    messagepack,
    cbor,
    bson,
};

/// Transformation configuration
pub const TransformationConfig = union(TransformationType) {
    minify: MinifyConfig,
    filter_fields: FilterConfig,
    validate_schema: SchemaConfig,
    convert_format: FormatConfig,
    custom: CustomTransformation,
};

/// Custom transformation function
pub const CustomTransformation = struct {
    /// Transformation function
    transform: TransformFunction,

    /// User data
    user_data: ?*anyopaque = null,

    /// Cleanup function
    cleanup: ?CleanupFunction = null,
};

/// Transform function signature
pub const TransformFunction = *const fn (
    token: Token,
    input_data: []const u8,
    output: *OutputStream,
    user_data: ?*anyopaque,
) anyerror!bool;

/// Cleanup function signature
pub const CleanupFunction = *const fn (user_data: ?*anyopaque) void;

/// A single transformation in the pipeline
pub const Transformation = struct {
    /// Transformation name for debugging and identification
    name: []const u8 = "unnamed",

    /// Transformation type and configuration
    config: TransformationConfig,

    /// Enabled flag
    enabled: bool = true,

    /// Priority (lower numbers = higher priority)
    priority: u32 = 0,

    pub fn init(config: TransformationConfig) Transformation {
        return Transformation{
            .config = config,
        };
    }

    pub fn withPriority(self: Transformation, priority: u32) Transformation {
        var trans = self;
        trans.priority = priority;
        return trans;
    }
};

/// Parallel execution engine
pub const ParallelEngine = struct {
    const Self = @This();

    /// Worker thread pool
    workers: std.Thread.Pool,

    /// Work distribution strategy
    distribution: WorkDistribution = .round_robin,

    pub fn init(allocator: Allocator) !Self {
        const workers = try std.Thread.Pool.init(.{
            .allocator = allocator,
            .n_jobs = 0, // Auto-detect
        });

        return Self{
            .workers = workers,
        };
    }

    pub fn deinit(self: *Self) void {
        self.workers.deinit();
    }

    pub fn executeParallel(
        self: *Self,
        pipeline: *TransformationPipeline,
        input: TokenStream,
        output: *OutputStream,
    ) !void {
        // TODO: Implement parallel execution
        _ = self;
        try pipeline.executeStreaming(input, output);
    }
};

/// Work distribution strategies
pub const WorkDistribution = enum {
    round_robin,
    chunk_based,
    load_balanced,
};

/// Memory manager for transformation pipeline
pub const MemoryManager = struct {
    const Self = @This();

    /// Allocator
    allocator: Allocator,

    /// Memory pools
    pools: std.AutoHashMap(usize, std.ArrayList([]u8)),

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .pools = std.AutoHashMap(usize, std.ArrayList([]u8)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.pools.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |block| {
                self.allocator.free(block);
            }
            entry.value_ptr.deinit();
        }
        self.pools.deinit();
    }

    pub fn allocate(self: *Self, size: usize) ![]u8 {
        const pool_key = getPoolKey(size);

        if (self.pools.get(pool_key)) |pool| {
            if (pool.items.len > 0) {
                return pool.orderedRemove(0);
            }
        }

        return self.allocator.alloc(u8, size);
    }

    pub fn release(self: *Self, buffer: []u8) void {
        const pool_key = getPoolKey(buffer.len);

        if (self.pools.get(pool_key)) |*pool| {
            pool.append(buffer) catch {
                self.allocator.free(buffer);
            };
        } else {
            var new_pool = std.ArrayList([]u8).init(self.allocator);
            new_pool.append(buffer) catch {
                self.allocator.free(buffer);
                return;
            };
            self.pools.put(pool_key, new_pool) catch {
                self.allocator.free(buffer);
            };
        }
    }

    fn getPoolKey(size: usize) usize {
        // Round up to nearest power of 2 for pool key
        var key: usize = 1;
        while (key < size) {
            key *= 2;
        }
        return key;
    }
};

/// Main transformation pipeline
pub const TransformationPipeline = struct {
    const Self = @This();

    /// Chain of transformations
    transformations: std.ArrayList(Transformation),

    /// Parallel execution engine
    parallel_engine: ?ParallelEngine = null,

    /// Memory manager
    memory_manager: MemoryManager,

    /// Pipeline statistics
    stats: PipelineStats,

    pub fn init(allocator: Allocator) !Self {
        const memory_manager = MemoryManager.init(allocator);

        return Self{
            .transformations = std.ArrayList(Transformation).init(allocator),
            .memory_manager = memory_manager,
            .stats = PipelineStats.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.parallel_engine) |*engine| {
            engine.deinit();
        }
        self.transformations.deinit();
        self.memory_manager.deinit();
    }

    pub fn addTransformation(
        self: *Self,
        transformation: Transformation,
    ) !void {
        try self.transformations.append(transformation);
        self.sortTransformations();
    }

    pub fn removeTransformation(self: *Self, index: usize) void {
        if (index < self.transformations.items.len) {
            _ = self.transformations.orderedRemove(index);
        }
    }

    pub fn clearTransformations(self: *Self) void {
        self.transformations.clearRetainingCapacity();
    }

    pub fn executeStreaming(
        self: *Self,
        input_stream: TokenStream,
        output_stream: *OutputStream,
    ) !void {
        self.stats.reset();
        const start_time = std.time.milliTimestamp();

        // Execute transformations in order
        var current_stream = input_stream;
        var temp_output = OutputStream.init(self.memory_manager.allocator);
        defer temp_output.deinit();

        for (self.transformations.items) |transformation| {
            if (!transformation.enabled) continue;

            self.stats.transformation_count += 1;
            const trans_start = std.time.milliTimestamp();

            try self.executeTransformation(transformation, &current_stream, &temp_output);

            const trans_end = std.time.milliTimestamp();
            self.stats.total_transformation_time += @as(u64, @intCast(trans_end - trans_start));

            // For multiple transformations, we'd need to re-parse the buffer
            // For now, just support single transformation
            if (self.transformations.items.len > 1) {
                return error.MultipleTransformationsNotImplemented;
            }
        }

        // Write final output
        if (self.transformations.items.len > 0) {
            const buffer = temp_output.getBuffer();
            try output_stream.write(buffer);
        } else {
            // No transformations, write original tokens
            for (0..current_stream.getTokenCount()) |i| {
                if (current_stream.getToken(i)) |token| {
                    try output_stream.writeToken(token, current_stream.input_data);
                }
            }
        }

        const end_time = std.time.milliTimestamp();
        self.stats.total_execution_time = @as(u64, @intCast(end_time - start_time));
    }

    fn executeTransformation(
        self: *Self,
        transformation: Transformation,
        input: *const TokenStream,
        output: *OutputStream,
    ) !void {
        switch (transformation.config) {
            .minify => |config| try self.executeMinify(config, input, output),
            .filter_fields => |config| try self.executeFilterFields(config, input, output),
            .validate_schema => |config| try self.executeSchemaValidation(config, input, output),
            .convert_format => |config| try self.executeFormatConversion(config, input, output),
            .custom => |config| try self.executeCustomTransformation(config, input, output),
        }
    }

    fn executeMinify(
        self: *Self,
        config: MinifyConfig,
        input: *const TokenStream,
        output: *OutputStream,
    ) !void {
        
        var pos: usize = 0;
        var prev_token_type: ?TokenType = null;
        
        while (pos < input.getTokenCount()) : (pos += 1) {
            const token = input.getToken(pos) orelse continue;
            
            switch (token.token_type) {
                .whitespace => {
                    // Skip whitespace if configured to remove it
                    if (config.remove_whitespace) {
                        continue;
                    }
                    // Otherwise, preserve minimal whitespace where needed
                    if (needsWhitespace(prev_token_type, getNextNonWhitespaceTokenType(input, pos))) {
                        try output.write(" ");
                    }
                },
                .comment => {
                    // Skip comments if configured to remove them
                    if (config.remove_comments) {
                        continue;
                    }
                    try output.writeToken(token, input.input_data);
                },
                .string => {
                    // Handle string minification
                    try self.writeMinifiedString(token, input.input_data, output, config);
                    prev_token_type = token.token_type;
                },
                .object_start, .object_end, .array_start, .array_end, .comma, .colon => {
                    // Structural tokens - write as-is without surrounding whitespace
                    try self.writeStructuralToken(token, input.input_data, output);
                    prev_token_type = token.token_type;
                },
                .number, .boolean_true, .boolean_false, .null => {
                    // Value tokens - write as-is
                    try output.writeToken(token, input.input_data);
                    prev_token_type = token.token_type;
                },
                .eof => {
                    // End of file - nothing to write
                    break;
                },
                .parse_error => {
                    // Propagate parse errors
                    return error.ParseError;
                },
            }
        }
    }
    
    fn writeMinifiedString(
        _: *Self,
        token: Token,
        input_data: []const u8,
        output: *OutputStream,
        config: MinifyConfig,
    ) !void {
        
        if (config.aggressive) {
            // For aggressive minification, we could potentially remove quotes 
            // from simple keys, but this would require more complex logic
            // For now, just write the string as-is
            try output.writeToken(token, input_data);
        } else {
            // Standard minification - preserve string exactly
            try output.writeToken(token, input_data);
        }
    }
    
    fn writeStructuralToken(
        _: *Self,
        token: Token,
        input_data: []const u8,
        output: *OutputStream,
    ) !void {
        
        // Write structural tokens using their canonical representation
        switch (token.token_type) {
            .object_start => try output.write("{"),
            .object_end => try output.write("}"),
            .array_start => try output.write("["),
            .array_end => try output.write("]"),
            .comma => try output.write(","),
            .colon => try output.write(":"),
            else => try output.writeToken(token, input_data),
        }
    }
    
    fn needsWhitespace(prev_type: ?TokenType, next_type: ?TokenType) bool {
        // Determine if whitespace is needed between two token types
        // This is conservative - we only add whitespace where absolutely necessary
        
        if (prev_type == null or next_type == null) return false;
        
        const prev = prev_type.?;
        const next = next_type.?;
        
        // Need space between two numbers to avoid concatenation
        if (prev == .number and next == .number) return true;
        
        // Need space between number and identifier-like tokens
        if (prev == .number and (next == .boolean_true or next == .boolean_false or next == .null)) return true;
        if ((prev == .boolean_true or prev == .boolean_false or prev == .null) and next == .number) return true;
        
        // Need space between boolean/null literals
        if ((prev == .boolean_true or prev == .boolean_false or prev == .null) and 
            (next == .boolean_true or next == .boolean_false or next == .null)) return true;
        
        return false;
    }
    
    fn getNextNonWhitespaceTokenType(input: *const TokenStream, start_pos: usize) ?TokenType {
        var pos = start_pos + 1;
        while (pos < input.getTokenCount()) : (pos += 1) {
            const token = input.getToken(pos) orelse continue;
            if (token.token_type != .whitespace and token.token_type != .comment) {
                return token.token_type;
            }
        }
        return null;
    }

    fn executeFilterFields(
        self: *Self,
        config: FilterConfig,
        input: *const TokenStream,
        output: *OutputStream,
    ) !void {
        const field_filter = @import("field_filter_v2.zig");
        try field_filter.executeFieldFiltering(config, input, output, self.memory_manager.allocator);
    }

    fn executeSchemaValidation(
        self: *Self,
        config: SchemaConfig,
        input: *const TokenStream,
        output: *OutputStream,
    ) !void {
        const schema_validation = @import("../schema_validation.zig");
        
        // Parse schema from JSON
        var schema = try schema_validation.Schema.fromJson(self.memory_manager.allocator, config.schema);
        defer {
            schema.deinit();
            self.memory_manager.allocator.destroy(schema);
        }
        
        // Create validator
        const validation_config = schema_validation.ValidationConfig{
            .fail_fast = (config.mode == .strict),
            .validate_formats = true,
            .strict_mode = (config.mode == .strict),
        };
        
        var validator = schema_validation.SchemaValidator.init(
            self.memory_manager.allocator,
            schema,
            validation_config,
        );
        
        // Validate the token stream
        var validation_state = try validator.validateTokenStream(input);
        defer validation_state.deinit();
        
        // Handle validation results
        if (!validation_state.isValid()) {
            if (config.mode == .strict) {
                // In strict mode, fail on validation errors
                const errors = validation_state.getErrors();
                if (errors.len > 0) {
                    std.log.err("Schema validation failed: {s}", .{errors[0].message});
                    return error.SchemaValidationFailed;
                }
            }
            // In permissive mode, log errors but continue
            const errors = validation_state.getErrors();
            for (errors) |err| {
                std.log.warn("Schema validation warning: {s} at {s}", .{ err.message, err.instance_path });
            }
        }
        
        // Pass through the input to output (validation doesn't modify content)
        var pos: usize = 0;
        while (pos < input.getTokenCount()) : (pos += 1) {
            const token = input.getToken(pos) orelse continue;
            try output.writeToken(token, input.input_data);
        }
        
        // Update stats
        self.stats.validation_errors += validation_state.getErrors().len;
        self.stats.nodes_validated += validation_state.nodes_validated;
    }

    fn executeFormatConversion(
        self: *Self,
        _config: FormatConfig,
        input: *const TokenStream,
        output: *OutputStream,
    ) !void {
        // TODO: Implement format conversion - for now just pass through
        var pos: usize = 0;
        while (pos < input.getTokenCount()) : (pos += 1) {
            const token = input.getToken(pos) orelse continue;
            try output.writeToken(token, input.input_data);
        }
        _ = self;
        _ = _config;
    }

    fn executeCustomTransformation(
        self: *Self,
        config: CustomTransformation,
        input: *const TokenStream,
        output: *OutputStream,
    ) !void {
        _ = self;
        var pos: usize = 0;
        while (pos < input.getTokenCount()) : (pos += 1) {
            const token = input.getToken(pos) orelse continue;

            const should_continue = try config.transform(token, input.input_data, output, config.user_data);
            if (!should_continue) break;
        }

        if (config.cleanup) |cleanup| {
            cleanup(config.user_data);
        }
    }

    fn sortTransformations(self: *Self) void {
        std.sort.insertion(Transformation, self.transformations.items, {}, struct {
            fn lessThan(_: void, a: Transformation, b: Transformation) bool {
                return a.priority < b.priority;
            }
        }.lessThan);
    }

    pub fn optimizePipeline(self: *Self) !void {
        _ = self;
        // TODO: Implement pipeline optimization
    }

    pub fn getStats(self: *Self) PipelineStats {
        return self.stats;
    }
};

/// Pipeline execution statistics
pub const PipelineStats = struct {
    /// Number of transformations executed
    transformation_count: usize = 0,

    /// Total execution time in milliseconds
    total_execution_time: u64 = 0,

    /// Total transformation time in milliseconds
    total_transformation_time: u64 = 0,

    /// Input tokens processed
    input_tokens: usize = 0,

    /// Output tokens generated
    output_tokens: usize = 0,

    /// Memory allocated
    memory_allocated: usize = 0,
    
    /// Validation errors encountered
    validation_errors: usize = 0,
    
    /// Nodes validated during schema validation
    nodes_validated: usize = 0,

    pub fn init() PipelineStats {
        return PipelineStats{};
    }

    pub fn reset(self: *PipelineStats) void {
        self.* = PipelineStats{};
    }

    pub fn getThroughput(self: PipelineStats) f64 {
        if (self.total_execution_time == 0) return 0.0;
        return @as(f64, @floatFromInt(self.output_tokens)) / (@as(f64, @floatFromInt(self.total_execution_time)) / 1000.0);
    }

    pub fn getMemoryEfficiency(self: PipelineStats) f64 {
        if (self.output_tokens == 0) return 0.0;
        return @as(f64, @floatFromInt(self.memory_allocated)) / @as(f64, @floatFromInt(self.output_tokens));
    }
};

test "TransformationPipeline basic functionality" {
    const allocator = std.testing.allocator;

    var pipeline = try TransformationPipeline.init(allocator);
    defer pipeline.deinit();

    // Add minification transformation
    try pipeline.addTransformation(Transformation.init(.{
        .minify = MinifyConfig{ .remove_whitespace = true },
    }));

    // Create test input
    const input_data = "{\"name\": \"test\", \"value\": 42}";
    var input_stream = TokenStream.init(allocator, input_data);
    defer input_stream.deinit();

    // Add some test tokens
    try input_stream.addToken(Token.init(.object_start, 0, 1, 1, 1));
    try input_stream.addToken(Token.init(.string, 1, 7, 1, 2));
    try input_stream.addToken(Token.init(.colon, 7, 8, 1, 8));
    try input_stream.addToken(Token.init(.whitespace, 8, 9, 1, 9));
    try input_stream.addToken(Token.init(.string, 9, 15, 1, 10));
    try input_stream.addToken(Token.init(.object_end, 15, 16, 1, 16));

    // Create output stream
    var output_stream = OutputStream.init(allocator);
    defer output_stream.deinit();

    // Execute pipeline
    try pipeline.executeStreaming(input_stream, &output_stream);

    // Verify output
    const output = output_stream.getBuffer();
    try std.testing.expect(output.len > 0);

    // Check stats
    const stats = pipeline.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.transformation_count);
    try std.testing.expect(stats.total_execution_time > 0);
}

test "OutputStream functionality" {
    const allocator = std.testing.allocator;

    var stream = OutputStream.init(allocator);
    defer stream.deinit();

    try stream.write("Hello, World!");
    try stream.write(" Test");

    const output = stream.getBuffer();
    try std.testing.expectEqualStrings("Hello, World! Test", output);

    stream.clear();
    try std.testing.expectEqual(@as(usize, 0), stream.getBuffer().len);
}
