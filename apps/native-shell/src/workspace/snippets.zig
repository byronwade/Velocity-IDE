//! Copyright (c) Microsoft Corporation. All rights reserved.
//! Bounded, literal-only workspace and optional user snippet configuration.

const std = @import("std");

pub const workspace_rel_path = ".velocity/snippets.json";
pub const schema_version: u32 = 1;
pub const max_snippets: usize = 32;
pub const max_file_bytes: usize = 16 * 1024;
pub const max_prefix_len: usize = 48;
pub const max_body_len: usize = 1024;
pub const max_description_len: usize = 160;
const json_scratch_bytes = max_file_bytes * 2;

pub const Snippet = struct {
    id: u32 = 0,
    prefix: []const u8 = "",
    body: []const u8 = "",
    description: []const u8 = "",
};

pub const LoadSummary = struct {
    loaded: u32 = 0,
    rejected: u32 = 0,
    user_loaded: bool = false,
    workspace_loaded: bool = false,
};

pub const LoadError = error{
    FileNotFound,
    AccessDenied,
    FileTooLarge,
    InvalidJson,
    InvalidSchema,
    UnsupportedVersion,
};

pub const Registry = struct {
    snippets: [max_snippets]Snippet = [_]Snippet{.{}} ** max_snippets,
    snippet_count: u32 = 0,
    prefix_pool: [max_snippets][max_prefix_len]u8 = undefined,
    prefix_lens: [max_snippets]usize = [_]usize{0} ** max_snippets,
    body_pool: [max_snippets][max_body_len]u8 = undefined,
    body_lens: [max_snippets]usize = [_]usize{0} ** max_snippets,
    description_pool: [max_snippets][max_description_len]u8 = undefined,
    description_lens: [max_snippets]usize = [_]usize{0} ** max_snippets,
    rejected_count: u32 = 0,

    pub fn slice(self: *const Registry) []const Snippet {
        return self.snippets[0..self.snippet_count];
    }

    pub fn clear(self: *Registry) void {
        self.snippet_count = 0;
        self.rejected_count = 0;
    }

    /// Loads user snippets first, then workspace snippets so workspace prefixes win.
    /// A missing or invalid source is skipped without discarding the other source.
    pub fn load(self: *Registry, io: std.Io, root_path: []const u8, user_path: []const u8) LoadSummary {
        self.clear();
        var summary: LoadSummary = .{};
        if (user_path.len > 0) {
            var user_buf: [max_file_bytes + 1]u8 = undefined;
            if (std.Io.Dir.cwd().readFile(io, user_path, &user_buf)) |data| {
                if (self.parseSource(data)) |_| {
                    summary.user_loaded = true;
                } else |_| {}
            } else |_| {}
        }
        if (root_path.len > 0) {
            var root = std.Io.Dir.cwd().openDir(io, root_path, .{}) catch {
                summary.loaded = self.snippet_count;
                summary.rejected = self.rejected_count;
                return summary;
            };
            defer root.close(io);
            var file_buf: [max_file_bytes + 1]u8 = undefined;
            if (root.readFile(io, workspace_rel_path, &file_buf)) |data| {
                if (data.len <= max_file_bytes) {
                    if (self.parseSource(data)) |_| {
                        summary.workspace_loaded = true;
                    } else |_| {}
                }
            } else |_| {}
        }
        summary.loaded = self.snippet_count;
        summary.rejected = self.rejected_count;
        return summary;
    }

    pub fn parseSource(self: *Registry, data: []const u8) LoadError!void {
        var source: Registry = .{};
        try source.parseDocument(data);
        self.rejected_count += source.rejected_count;
        for (source.slice()) |snippet| self.upsert(snippet.prefix, snippet.body, snippet.description);
    }

    fn parseDocument(self: *Registry, data: []const u8) LoadError!void {
        if (data.len > max_file_bytes) return error.FileTooLarge;
        var scratch: [json_scratch_bytes]u8 = undefined;
        var fixed = std.heap.FixedBufferAllocator.init(&scratch);
        const allocator = fixed.allocator();
        var json = std.json.Scanner.initCompleteInput(allocator, data);
        defer json.deinit();
        if ((next(&json, allocator) catch return error.InvalidJson) != .object_begin) return error.InvalidJson;

        var saw_version = false;
        var saw_snippets = false;
        while (true) {
            const key_token = next(&json, allocator) catch return error.InvalidJson;
            if (key_token == .object_end) break;
            const key = tokenString(key_token) orelse return error.InvalidJson;
            if (std.mem.eql(u8, key, "version")) {
                if (saw_version) return error.InvalidSchema;
                saw_version = true;
                const raw = tokenNumber(next(&json, allocator) catch return error.InvalidJson) orelse return error.InvalidSchema;
                const version = std.fmt.parseInt(u32, raw, 10) catch return error.InvalidSchema;
                if (version != schema_version) return error.UnsupportedVersion;
            } else if (std.mem.eql(u8, key, "snippets")) {
                if (saw_snippets) return error.InvalidSchema;
                saw_snippets = true;
                try self.parseSnippets(&json, allocator);
            } else {
                return error.InvalidSchema;
            }
        }
        if (!saw_version or !saw_snippets) return error.InvalidSchema;
        if ((next(&json, allocator) catch return error.InvalidJson) != .end_of_document) return error.InvalidJson;
    }

    fn parseSnippets(self: *Registry, json: *std.json.Scanner, allocator: std.mem.Allocator) LoadError!void {
        if ((next(json, allocator) catch return error.InvalidJson) != .array_begin) return error.InvalidSchema;
        while (true) {
            const token = next(json, allocator) catch return error.InvalidJson;
            if (token == .array_end) break;
            if (token != .object_begin) return error.InvalidSchema;
            try self.parseSnippet(json, allocator);
        }
    }

    fn parseSnippet(self: *Registry, json: *std.json.Scanner, allocator: std.mem.Allocator) LoadError!void {
        var prefix: []const u8 = "";
        var body: []const u8 = "";
        var description: []const u8 = "";
        var valid = true;
        var saw_prefix = false;
        var saw_body = false;
        var saw_description = false;
        while (true) {
            const key_token = next(json, allocator) catch return error.InvalidJson;
            if (key_token == .object_end) break;
            const key = tokenString(key_token) orelse return error.InvalidJson;
            const value = tokenString(next(json, allocator) catch return error.InvalidJson) orelse return error.InvalidSchema;
            if (std.mem.eql(u8, key, "prefix")) {
                if (saw_prefix) return error.InvalidSchema;
                saw_prefix = true;
                prefix = value;
                valid = valid and value.len > 0 and value.len <= max_prefix_len;
            } else if (std.mem.eql(u8, key, "body")) {
                if (saw_body) return error.InvalidSchema;
                saw_body = true;
                body = value;
                valid = valid and value.len > 0 and value.len <= max_body_len and isLiteralBody(value);
            } else if (std.mem.eql(u8, key, "description")) {
                if (saw_description) return error.InvalidSchema;
                saw_description = true;
                description = value;
                valid = valid and value.len <= max_description_len;
            } else {
                return error.InvalidSchema;
            }
        }
        valid = valid and saw_prefix and saw_body and saw_description;
        if (!valid) {
            self.rejected_count += 1;
            return;
        }
        self.upsert(prefix, body, description);
    }

    fn upsert(self: *Registry, prefix: []const u8, body: []const u8, description: []const u8) void {
        var index: usize = self.snippet_count;
        for (self.slice(), 0..) |snippet, candidate| {
            if (std.mem.eql(u8, snippet.prefix, prefix)) {
                index = candidate;
                break;
            }
        }
        if (index == self.snippet_count) {
            if (self.snippet_count >= max_snippets) {
                self.rejected_count += 1;
                return;
            }
            self.snippet_count += 1;
        }
        copyInto(&self.prefix_pool[index], &self.prefix_lens[index], prefix);
        copyInto(&self.body_pool[index], &self.body_lens[index], body);
        copyInto(&self.description_pool[index], &self.description_lens[index], description);
        self.snippets[index] = .{
            .id = @intCast(index + 1),
            .prefix = self.prefix_pool[index][0..self.prefix_lens[index]],
            .body = self.body_pool[index][0..self.body_lens[index]],
            .description = self.description_pool[index][0..self.description_lens[index]],
        };
    }
};

fn next(json: *std.json.Scanner, allocator: std.mem.Allocator) !std.json.Token {
    return json.nextAllocMax(allocator, .alloc_if_needed, max_file_bytes);
}

fn tokenString(token: std.json.Token) ?[]const u8 {
    return switch (token) {
        .string, .allocated_string => |value| value,
        else => null,
    };
}

fn tokenNumber(token: std.json.Token) ?[]const u8 {
    return switch (token) {
        .number, .allocated_number => |value| value,
        else => null,
    };
}

fn copyInto(out: []u8, len: *usize, value: []const u8) void {
    @memcpy(out[0..value.len], value);
    len.* = value.len;
}

fn isLiteralBody(body: []const u8) bool {
    if (std.mem.indexOf(u8, body, "$(") != null or std.mem.indexOfScalar(u8, body, '`') != null) return false;
    var index: usize = 0;
    while (index < body.len) : (index += 1) {
        if (body[index] != '$') continue;
        if (index + 1 < body.len and std.ascii.isDigit(body[index + 1])) return false;
        if (index + 1 < body.len and body[index + 1] == '{') return false;
    }
    return true;
}

test "workspace source overrides user prefix and rejects dynamic bodies" {
    var registry: Registry = .{};
    try registry.parseSource(
        \\{"version":1,"snippets":[
        \\{"prefix":"log","body":"user","description":"user"},
        \\{"prefix":"bad","body":"${1:value}","description":"dynamic"}
        \\]}
    );
    try registry.parseSource(
        \\{"version":1,"snippets":[
        \\{"prefix":"log","body":"workspace","description":"workspace"}
        \\]}
    );
    try std.testing.expectEqual(@as(u32, 1), registry.snippet_count);
    try std.testing.expectEqual(@as(u32, 1), registry.rejected_count);
    try std.testing.expectEqualStrings("workspace", registry.snippets[0].body);
}

test "snippet schema is versioned and bounded" {
    var registry: Registry = .{};
    try std.testing.expectError(error.UnsupportedVersion, registry.parseSource(
        \\{"version":2,"snippets":[]}
    ));
    var oversized: [max_body_len + 1]u8 = [_]u8{'x'} ** (max_body_len + 1);
    var source: [max_file_bytes]u8 = undefined;
    const data = try std.fmt.bufPrint(&source, "{{\"version\":1,\"snippets\":[{{\"prefix\":\"large\",\"body\":\"{s}\",\"description\":\"large\"}}]}}", .{&oversized});
    try registry.parseSource(data);
    try std.testing.expectEqual(@as(u32, 0), registry.snippet_count);
    try std.testing.expectEqual(@as(u32, 1), registry.rejected_count);
}

test "optional user file loads and workspace prefix overrides it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "user-snippets.json",
        .data =
        \\{"version":1,"snippets":[
        \\{"prefix":"component","body":"user body","description":"user component"},
        \\{"prefix":"user-only","body":"literal user","description":"user only"}
        \\]}
        ,
    });
    var user_path_buf: [160]u8 = undefined;
    const user_path = try std.fmt.bufPrint(&user_path_buf, ".zig-cache/tmp/{s}/user-snippets.json", .{tmp.sub_path});
    var registry: Registry = .{};
    const summary = registry.load(std.testing.io, "fixtures/acme-dashboard", user_path);
    try std.testing.expect(summary.user_loaded);
    try std.testing.expect(summary.workspace_loaded);
    try std.testing.expectEqual(@as(u32, 3), summary.loaded);
    for (registry.slice()) |snippet| {
        if (std.mem.eql(u8, snippet.prefix, "component")) {
            try std.testing.expect(std.mem.indexOf(u8, snippet.body, "FixtureSnippet") != null);
            return;
        }
    }
    return error.TestExpectedEqual;
}
