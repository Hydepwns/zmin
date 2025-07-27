const std = @import("std");
const print = std.debug.print;
const json = std.json;

// API Documentation Generator for zmin
// Extracts documentation from Zig source files and generates OpenAPI specs

const DocComment = struct {
    line: u32,
    content: []const u8,
};

const FunctionDoc = struct {
    name: []const u8,
    doc_comment: ?[]const u8,
    params: []Parameter,
    return_type: []const u8,
    is_public: bool,
    file: []const u8,
    line: u32,
};

const Parameter = struct {
    name: []const u8,
    type: []const u8,
    doc: ?[]const u8,
};

const TypeDoc = struct {
    name: []const u8,
    kind: TypeKind,
    doc_comment: ?[]const u8,
    fields: []Field,
    file: []const u8,
    line: u32,
};

const TypeKind = enum {
    Struct,
    Enum,
    Union,
    Error,
};

const Field = struct {
    name: []const u8,
    type: []const u8,
    doc: ?[]const u8,
};

const ApiDocGenerator = struct {
    allocator: std.mem.Allocator,
    functions: std.ArrayList(FunctionDoc),
    types: std.ArrayList(TypeDoc),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .functions = std.ArrayList(FunctionDoc).init(allocator),
            .types = std.ArrayList(TypeDoc).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.functions.deinit();
        self.types.deinit();
    }
    
    pub fn scanDirectory(self: *Self, dir_path: []const u8) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => {
                print("Directory not found: {s}\n", .{dir_path});
                return;
            },
            else => return err,
        };
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
                const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer self.allocator.free(full_path);
                
                try self.parseFile(full_path);
            } else if (entry.kind == .directory) {
                const sub_dir = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer self.allocator.free(sub_dir);
                
                try self.scanDirectory(sub_dir);
            }
        }
    }
    
    fn parseFile(self: *Self, file_path: []const u8) !void {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();
        
        const file_size = try file.getEndPos();
        const content = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(content);
        
        _ = try file.readAll(content);
        
        try self.parseContent(content, file_path);
    }
    
    fn parseContent(self: *Self, content: []const u8, file_path: []const u8) !void {
        var lines = std.mem.split(u8, content, "\n");
        var line_number: u32 = 0;
        var current_doc_comment: ?[]const u8 = null;
        
        while (lines.next()) |line| {
            line_number += 1;
            const trimmed = std.mem.trim(u8, line, " \t\r");
            
            // Extract doc comments
            if (std.mem.startsWith(u8, trimmed, "///")) {
                const comment = std.mem.trim(u8, trimmed[3..], " ");
                if (current_doc_comment) |existing| {
                    const combined = try std.fmt.allocPrint(self.allocator, "{s}\n{s}", .{ existing, comment });
                    self.allocator.free(existing);
                    current_doc_comment = combined;
                } else {
                    current_doc_comment = try self.allocator.dupe(u8, comment);
                }
                continue;
            }
            
            // Parse public functions
            if (std.mem.startsWith(u8, trimmed, "pub fn ")) {
                try self.parseFunction(trimmed, file_path, line_number, current_doc_comment);
                current_doc_comment = null;
            }
            // Parse public types
            else if (std.mem.startsWith(u8, trimmed, "pub const ") and 
                     (std.mem.indexOf(u8, trimmed, " struct ") != null or
                      std.mem.indexOf(u8, trimmed, " enum ") != null or
                      std.mem.indexOf(u8, trimmed, " union ") != null)) {
                try self.parseType(trimmed, file_path, line_number, current_doc_comment);
                current_doc_comment = null;
            }
            // Clear doc comment if we hit non-doc line
            else if (!std.mem.startsWith(u8, trimmed, "//") and trimmed.len > 0) {
                if (current_doc_comment) |doc| {
                    self.allocator.free(doc);
                    current_doc_comment = null;
                }
            }
        }
        
        if (current_doc_comment) |doc| {
            self.allocator.free(doc);
        }
    }
    
    fn parseFunction(self: *Self, line: []const u8, file_path: []const u8, line_number: u32, doc_comment: ?[]const u8) !void {
        // Extract function name from "pub fn functionName(...) return_type"
        const fn_start = std.mem.indexOf(u8, line, "fn ") orelse return;
        const name_start = fn_start + 3;
        const paren_pos = std.mem.indexOf(u8, line[name_start..], "(") orelse return;
        const name = line[name_start..name_start + paren_pos];
        
        // Extract return type (simplified)
        var return_type: []const u8 = "void";
        if (std.mem.indexOf(u8, line, ") ")) |ret_start| {
            const ret_part = std.mem.trim(u8, line[ret_start + 2..], " {");
            if (ret_part.len > 0) {
                return_type = try self.allocator.dupe(u8, ret_part);
            }
        }
        
        const func_doc = FunctionDoc{
            .name = try self.allocator.dupe(u8, name),
            .doc_comment = if (doc_comment) |doc| try self.allocator.dupe(u8, doc) else null,
            .params = &[_]Parameter{}, // TODO: Parse parameters
            .return_type = return_type,
            .is_public = true,
            .file = try self.allocator.dupe(u8, file_path),
            .line = line_number,
        };
        
        try self.functions.append(func_doc);
    }
    
    fn parseType(self: *Self, line: []const u8, file_path: []const u8, line_number: u32, doc_comment: ?[]const u8) !void {
        // Extract type name from "pub const TypeName = struct/enum/union"
        const const_start = std.mem.indexOf(u8, line, "const ") orelse return;
        const name_start = const_start + 6;
        const eq_pos = std.mem.indexOf(u8, line[name_start..], " =") orelse return;
        const name = line[name_start..name_start + eq_pos];
        
        var kind = TypeKind.Struct;
        if (std.mem.indexOf(u8, line, " enum ") != null) {
            kind = TypeKind.Enum;
        } else if (std.mem.indexOf(u8, line, " union ") != null) {
            kind = TypeKind.Union;
        }
        
        const type_doc = TypeDoc{
            .name = try self.allocator.dupe(u8, name),
            .kind = kind,
            .doc_comment = if (doc_comment) |doc| try self.allocator.dupe(u8, doc) else null,
            .fields = &[_]Field{}, // TODO: Parse fields
            .file = try self.allocator.dupe(u8, file_path),
            .line = line_number,
        };
        
        try self.types.append(type_doc);
    }
    
    pub fn generateOpenApiSpec(self: *Self) ![]const u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();
        
        // Create OpenAPI structure
        var spec = std.StringArrayHashMap(json.Value).init(arena_allocator);
        
        // Basic info
        var info = std.StringArrayHashMap(json.Value).init(arena_allocator);
        try info.put("title", json.Value{ .string = "zmin - Zig JSON Minifier Library" });
        try info.put("version", json.Value{ .string = "1.0.0" });
        try info.put("description", json.Value{ .string = "Auto-generated API documentation from Zig source code" });
        
        try spec.put("openapi", json.Value{ .string = "3.0.3" });
        try spec.put("info", json.Value{ .object = info });
        
        // Generate paths from functions
        var paths = std.StringArrayHashMap(json.Value).init(arena_allocator);
        
        for (self.functions.items) |func| {
            const path_name = try std.fmt.allocPrint(arena_allocator, "/{s}", .{func.name});
            
            var operation = std.StringArrayHashMap(json.Value).init(arena_allocator);
            try operation.put("summary", json.Value{ .string = func.name });
            
            if (func.doc_comment) |doc| {
                try operation.put("description", json.Value{ .string = doc });
            }
            
            var tags_array = std.ArrayList(json.Value).init(arena_allocator);
            try tags_array.append(json.Value{ .string = "Zig Functions" });
            try operation.put("tags", json.Value{ .array = tags_array.items });
            
            var responses = std.StringArrayHashMap(json.Value).init(arena_allocator);
            var success_response = std.StringArrayHashMap(json.Value).init(arena_allocator);
            try success_response.put("description", json.Value{ .string = "Success" });
            try responses.put("200", json.Value{ .object = success_response });
            try operation.put("responses", json.Value{ .object = responses });
            
            var method = std.StringArrayHashMap(json.Value).init(arena_allocator);
            try method.put("post", json.Value{ .object = operation });
            
            try paths.put(path_name, json.Value{ .object = method });
        }
        
        try spec.put("paths", json.Value{ .object = paths });
        
        // Generate components from types
        var components = std.StringArrayHashMap(json.Value).init(arena_allocator);
        var schemas = std.StringArrayHashMap(json.Value).init(arena_allocator);
        
        for (self.types.items) |type_doc| {
            var schema = std.StringArrayHashMap(json.Value).init(arena_allocator);
            
            switch (type_doc.kind) {
                .Struct => {
                    try schema.put("type", json.Value{ .string = "object" });
                },
                .Enum => {
                    try schema.put("type", json.Value{ .string = "string" });
                },
                else => {
                    try schema.put("type", json.Value{ .string = "object" });
                },
            }
            
            if (type_doc.doc_comment) |doc| {
                try schema.put("description", json.Value{ .string = doc });
            }
            
            try schemas.put(type_doc.name, json.Value{ .object = schema });
        }
        
        try components.put("schemas", json.Value{ .object = schemas });
        try spec.put("components", json.Value{ .object = components });
        
        // Convert to JSON string
        var output = std.ArrayList(u8).init(self.allocator);
        try json.stringify(json.Value{ .object = spec }, .{}, output.writer());
        
        return output.toOwnedSlice();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        print("Usage: {s} <source_directory> [output_file]\n", .{args[0]});
        return;
    }
    
    const source_dir = args[1];
    const output_file = if (args.len >= 3) args[2] else "docs/api-reference-generated.json";
    
    var generator = ApiDocGenerator.init(allocator);
    defer generator.deinit();
    
    print("Scanning source directory: {s}\n", .{source_dir});
    try generator.scanDirectory(source_dir);
    
    print("Found {} functions and {} types\n", .{ generator.functions.items.len, generator.types.items.len });
    
    const spec_json = try generator.generateOpenApiSpec();
    defer allocator.free(spec_json);
    
    // Write to output file
    const file = try std.fs.cwd().createFile(output_file, .{});
    defer file.close();
    
    try file.writeAll(spec_json);
    
    print("Generated API documentation: {s}\n", .{output_file});
}