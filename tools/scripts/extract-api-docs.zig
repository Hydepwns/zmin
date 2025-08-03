const std = @import("std");
const fs = std.fs;
const json = std.json;

const ApiDoc = struct {
    name: []const u8,
    type: []const u8, // function, struct, enum, const
    signature: ?[]const u8,
    description: []const u8,
    params: ?[]Param,
    returns: ?[]const u8,
    examples: ?[][]const u8,
    since: ?[]const u8,
    deprecated: ?[]const u8,
};

const Param = struct {
    name: []const u8,
    type: []const u8,
    description: []const u8,
    optional: bool = false,
    default: ?[]const u8 = null,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.debug.print("Usage: {s} <source_dir> <output_file>\n", .{args[0]});
        return;
    }

    const source_dir = args[1];
    const output_file = args[2];

    var api_docs = std.ArrayList(ApiDoc).init(allocator);
    defer api_docs.deinit();

    // Scan source directory
    try scanDirectory(allocator, source_dir, &api_docs);

    // Generate JSON output
    try generateJson(allocator, &api_docs, output_file);
}

fn scanDirectory(allocator: std.mem.Allocator, path: []const u8, docs: *std.ArrayList(ApiDoc)) !void {
    var dir = try fs.openDirAbsolute(path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const full_path = try fs.path.join(allocator, &[_][]const u8{ path, entry.name });
            defer allocator.free(full_path);

            try parseZigFile(allocator, full_path, docs);
        } else if (entry.kind == .directory) {
            const sub_path = try fs.path.join(allocator, &[_][]const u8{ path, entry.name });
            defer allocator.free(sub_path);

            try scanDirectory(allocator, sub_path, docs);
        }
    }
}

fn parseZigFile(allocator: std.mem.Allocator, file_path: []const u8, docs: *std.ArrayList(ApiDoc)) !void {
    const file = try fs.openFileAbsolute(file_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var lines = std.mem.tokenize(u8, content, "\n");
    var doc_comment = std.ArrayList([]const u8).init(allocator);
    defer doc_comment.deinit();

    var line_num: usize = 0;
    while (lines.next()) |line| {
        line_num += 1;

        // Collect doc comments
        if (std.mem.startsWith(u8, std.mem.trim(u8, line, " \t"), "///")) {
            const comment = std.mem.trim(u8, line[3..], " ");
            try doc_comment.append(try allocator.dupe(u8, comment));
            continue;
        }

        // Check for public declarations
        if (std.mem.startsWith(u8, std.mem.trim(u8, line, " \t"), "pub ")) {
            if (doc_comment.items.len > 0) {
                // Parse the declaration
                if (std.mem.indexOf(u8, line, "pub fn ")) |_| {
                    try parseFunctionDecl(allocator, line, &doc_comment, docs);
                } else if (std.mem.indexOf(u8, line, "pub const ")) |_| {
                    try parseConstDecl(allocator, line, &doc_comment, docs);
                } else if (std.mem.indexOf(u8, line, "pub const struct") != null or
                          std.mem.indexOf(u8, line, "pub struct") != null) {
                    try parseStructDecl(allocator, line, &doc_comment, docs);
                } else if (std.mem.indexOf(u8, line, "pub const enum") != null or
                          std.mem.indexOf(u8, line, "pub enum") != null) {
                    try parseEnumDecl(allocator, line, &doc_comment, docs);
                }
            }
            doc_comment.clearRetainingCapacity();
        } else if (!std.mem.startsWith(u8, std.mem.trim(u8, line, " \t"), "//")) {
            // Clear comments if we hit non-comment, non-declaration line
            doc_comment.clearRetainingCapacity();
        }
    }
}

fn parseFunctionDecl(
    allocator: std.mem.Allocator,
    line: []const u8,
    doc_comment: *std.ArrayList([]const u8),
    docs: *std.ArrayList(ApiDoc),
) !void {
    // Extract function name and signature
    const fn_start = std.mem.indexOf(u8, line, "pub fn ").? + 7;
    const fn_end = std.mem.indexOf(u8, line[fn_start..], "(") orelse return;
    const fn_name = std.mem.trim(u8, line[fn_start..][0..fn_end], " ");

    // Extract full signature
    var signature = std.ArrayList(u8).init(allocator);
    defer signature.deinit();
    try signature.appendSlice(line);

    // Parse documentation
    var description = std.ArrayList(u8).init(allocator);
    defer description.deinit();
    
    var params = std.ArrayList(Param).init(allocator);
    defer params.deinit();
    
    var returns: ?[]const u8 = null;
    var examples = std.ArrayList([]const u8).init(allocator);
    defer examples.deinit();

    for (doc_comment.items) |comment| {
        if (std.mem.startsWith(u8, comment, "@param ")) {
            // Parse parameter documentation
            const param_doc = comment[7..];
            if (std.mem.indexOf(u8, param_doc, " - ")) |sep| {
                const param_name = std.mem.trim(u8, param_doc[0..sep], " ");
                const param_desc = std.mem.trim(u8, param_doc[sep + 3..], " ");
                
                try params.append(.{
                    .name = try allocator.dupe(u8, param_name),
                    .type = try allocator.dupe(u8, ""), // TODO: Extract from signature
                    .description = try allocator.dupe(u8, param_desc),
                });
            }
        } else if (std.mem.startsWith(u8, comment, "@return ")) {
            returns = try allocator.dupe(u8, comment[8..]);
        } else if (std.mem.startsWith(u8, comment, "@example ")) {
            try examples.append(try allocator.dupe(u8, comment[9..]));
        } else {
            if (description.items.len > 0) try description.append(' ');
            try description.appendSlice(comment);
        }
    }

    try docs.append(.{
        .name = try allocator.dupe(u8, fn_name),
        .type = "function",
        .signature = try allocator.dupe(u8, signature.items),
        .description = try allocator.dupe(u8, description.items),
        .params = if (params.items.len > 0) try allocator.dupe(Param, params.items) else null,
        .returns = returns,
        .examples = if (examples.items.len > 0) try allocator.dupe([]const u8, examples.items) else null,
        .since = null,
        .deprecated = null,
    });
}

fn parseConstDecl(
    allocator: std.mem.Allocator,
    line: []const u8,
    doc_comment: *std.ArrayList([]const u8),
    docs: *std.ArrayList(ApiDoc),
) !void {
    const const_start = std.mem.indexOf(u8, line, "pub const ").? + 10;
    const const_end = std.mem.indexOf(u8, line[const_start..], " ") orelse 
                     std.mem.indexOf(u8, line[const_start..], "=") orelse 
                     return;
    const const_name = std.mem.trim(u8, line[const_start..][0..const_end], " ");

    var description = std.ArrayList(u8).init(allocator);
    defer description.deinit();
    
    for (doc_comment.items) |comment| {
        if (description.items.len > 0) try description.append(' ');
        try description.appendSlice(comment);
    }

    try docs.append(.{
        .name = try allocator.dupe(u8, const_name),
        .type = "constant",
        .signature = try allocator.dupe(u8, line),
        .description = try allocator.dupe(u8, description.items),
        .params = null,
        .returns = null,
        .examples = null,
        .since = null,
        .deprecated = null,
    });
}

fn parseStructDecl(
    allocator: std.mem.Allocator,
    line: []const u8,
    doc_comment: *std.ArrayList([]const u8),
    docs: *std.ArrayList(ApiDoc),
) !void {
    // Extract struct name
    var name: []const u8 = undefined;
    if (std.mem.indexOf(u8, line, "pub const ")) |pos| {
        const after_const = line[pos + 10..];
        if (std.mem.indexOf(u8, after_const, " ")) |space| {
            name = std.mem.trim(u8, after_const[0..space], " ");
        } else return;
    } else if (std.mem.indexOf(u8, line, "pub struct")) |_| {
        // Anonymous struct, skip for now
        return;
    } else return;

    var description = std.ArrayList(u8).init(allocator);
    defer description.deinit();
    
    for (doc_comment.items) |comment| {
        if (description.items.len > 0) try description.append(' ');
        try description.appendSlice(comment);
    }

    try docs.append(.{
        .name = try allocator.dupe(u8, name),
        .type = "struct",
        .signature = null,
        .description = try allocator.dupe(u8, description.items),
        .params = null,
        .returns = null,
        .examples = null,
        .since = null,
        .deprecated = null,
    });
}

fn parseEnumDecl(
    allocator: std.mem.Allocator,
    line: []const u8,
    doc_comment: *std.ArrayList([]const u8),
    docs: *std.ArrayList(ApiDoc),
) !void {
    // Similar to parseStructDecl
    var name: []const u8 = undefined;
    if (std.mem.indexOf(u8, line, "pub const ")) |pos| {
        const after_const = line[pos + 10..];
        if (std.mem.indexOf(u8, after_const, " ")) |space| {
            name = std.mem.trim(u8, after_const[0..space], " ");
        } else return;
    } else return;

    var description = std.ArrayList(u8).init(allocator);
    defer description.deinit();
    
    for (doc_comment.items) |comment| {
        if (description.items.len > 0) try description.append(' ');
        try description.appendSlice(comment);
    }

    try docs.append(.{
        .name = try allocator.dupe(u8, name),
        .type = "enum",
        .signature = null,
        .description = try allocator.dupe(u8, description.items),
        .params = null,
        .returns = null,
        .examples = null,
        .since = null,
        .deprecated = null,
    });
}

fn generateJson(
    allocator: std.mem.Allocator,
    docs: *std.ArrayList(ApiDoc),
    output_file: []const u8,
) !void {
    // Create output structure
    const output = .{
        .version = "1.0.0",
        .generated = "2024-01-01T00:00:00Z", // TODO: Use actual timestamp
        .api = docs.items,
    };

    // Serialize to JSON
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try json.stringify(output, .{ .whitespace = .indent_2 }, buffer.writer());

    // Write to file
    const file = try fs.createFileAbsolute(output_file, .{});
    defer file.close();

    try file.writeAll(buffer.items);
    
    std.debug.print("Generated API documentation: {s}\n", .{output_file});
    std.debug.print("Documented items: {d}\n", .{docs.items.len});
}