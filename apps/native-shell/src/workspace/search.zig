//! Bounded in-workspace text search (no ripgrep process).
//! Scans already-loaded file nodes; reads up to max_file_bytes per file.

const std = @import("std");
const scanner = @import("../workspace/scanner.zig");
const workspace_store = @import("../workspace/workspace_store.zig");

pub const max_hits: usize = 64;
pub const max_query: usize = 64;
pub const max_preview: usize = 120;
pub const max_path_pattern: usize = 96;

pub const Options = struct {
    case_sensitive: bool = false,
    whole_word: bool = false,
    include: []const u8 = "",
    exclude: []const u8 = "",
};

pub const SearchHit = struct {
    id: u32 = 0,
    path: []const u8 = "",
    line: u32 = 0,
    preview: []const u8 = "",
};

pub const SearchBuffers = struct {
    hits: [max_hits]SearchHit = [_]SearchHit{.{}} ** max_hits,
    hit_count: u32 = 0,
    path_pool: [max_hits][scanner.max_rel_path_len]u8 = undefined,
    path_lens: [max_hits]usize = [_]usize{0} ** max_hits,
    preview_pool: [max_hits][max_preview]u8 = undefined,
    preview_lens: [max_hits]usize = [_]usize{0} ** max_hits,
    status: []const u8 = "idle",
    status_buf: [48]u8 = undefined,

    pub fn hitsSlice(self: *SearchBuffers) []const SearchHit {
        return self.hits[0..self.hit_count];
    }

    pub fn clear(self: *SearchBuffers) void {
        self.hit_count = 0;
        self.status = "idle";
    }

    pub fn search(
        self: *SearchBuffers,
        io: std.Io,
        ws: *workspace_store.WorkspaceBuffers,
        query: []const u8,
    ) void {
        self.searchWithOptions(io, ws, query, false);
    }

    pub fn searchWithOptions(
        self: *SearchBuffers,
        io: std.Io,
        ws: *workspace_store.WorkspaceBuffers,
        query: []const u8,
        case_sensitive: bool,
    ) void {
        self.searchScoped(io, ws, query, .{ .case_sensitive = case_sensitive });
    }

    pub fn searchScoped(
        self: *SearchBuffers,
        io: std.Io,
        ws: *workspace_store.WorkspaceBuffers,
        query: []const u8,
        options: Options,
    ) void {
        self.clear();
        const needle = std.mem.trim(u8, query, " \t");
        if (needle.len == 0) {
            self.status = "empty query";
            return;
        }
        self.status = "searching";
        var file_buf: [scanner.max_file_bytes]u8 = undefined;
        var i: u32 = 0;
        while (i < ws.file_node_count and self.hit_count < max_hits) : (i += 1) {
            const node = ws.file_nodes[i];
            if (node.is_dir) continue;
            if (!pathInScope(node.path, options.include, options.exclude)) continue;
            const n = scanner.readTextFile(io, ws.rootPath(), node.path, file_buf[0..]) catch continue;
            self.scanFile(node.path, file_buf[0..n], needle, options);
        }
        if (self.hit_count == 0) {
            self.status = "no matches";
        } else {
            self.status = std.fmt.bufPrint(&self.status_buf, "{d} hits", .{self.hit_count}) catch "done";
        }
    }

    fn scanFile(self: *SearchBuffers, path: []const u8, content: []const u8, query: []const u8, options: Options) void {
        var line_no: u32 = 1;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= content.len and self.hit_count < max_hits) : (i += 1) {
            if (i == content.len or content[i] == '\n') {
                const line = content[start..i];
                const hit = indexMatch(line, query, options.case_sensitive, options.whole_word) != null;
                if (hit) self.pushHit(path, line_no, line);
                line_no += 1;
                start = i + 1;
            }
        }
    }

    fn pushHit(self: *SearchBuffers, path: []const u8, line: u32, preview_src: []const u8) void {
        if (self.hit_count >= max_hits) return;
        const idx = self.hit_count;
        const plen = @min(path.len, self.path_pool[idx].len);
        @memcpy(self.path_pool[idx][0..plen], path[0..plen]);
        self.path_lens[idx] = plen;
        const trimmed = std.mem.trim(u8, preview_src, " \t\r");
        const vlen = @min(trimmed.len, self.preview_pool[idx].len);
        @memcpy(self.preview_pool[idx][0..vlen], trimmed[0..vlen]);
        self.preview_lens[idx] = vlen;
        self.hits[idx] = .{
            .id = idx + 1,
            .path = self.path_pool[idx][0..plen],
            .line = line,
            .preview = self.preview_pool[idx][0..vlen],
        };
        self.hit_count += 1;
    }
};

/// Comma-separated, bounded patterns. `*` matches any characters. A pattern
/// without `*` matches either an exact path prefix or exact path suffix.
pub fn pathInScope(path: []const u8, include: []const u8, exclude: []const u8) bool {
    const included = std.mem.trim(u8, include, " \t").len == 0 or matchesPatternList(path, include);
    return included and !matchesPatternList(path, exclude);
}

pub fn indexMatch(text: []const u8, needle: []const u8, case_sensitive: bool, whole_word: bool) ?usize {
    if (needle.len == 0) return null;
    var offset: usize = 0;
    while (offset + needle.len <= text.len) {
        const relative = if (case_sensitive)
            std.mem.indexOf(u8, text[offset..], needle)
        else
            std.ascii.indexOfIgnoreCase(text[offset..], needle);
        const found = relative orelse return null;
        const index = offset + found;
        if (!whole_word or isWholeWord(text, index, index + needle.len)) return index;
        offset = index + 1;
    }
    return null;
}

fn matchesPatternList(path: []const u8, patterns: []const u8) bool {
    var iterator = std.mem.splitScalar(u8, patterns[0..@min(patterns.len, max_path_pattern)], ',');
    while (iterator.next()) |raw| {
        const pattern = std.mem.trim(u8, raw, " \t");
        if (pattern.len == 0) continue;
        if (globMatch(path, pattern)) return true;
    }
    return false;
}

fn globMatch(path: []const u8, pattern: []const u8) bool {
    if (std.mem.indexOfScalar(u8, pattern, '*') == null) {
        return std.mem.startsWith(u8, path, pattern) or std.mem.endsWith(u8, path, pattern);
    }
    var path_index: usize = 0;
    var pattern_index: usize = 0;
    var star_index: ?usize = null;
    var retry_path: usize = 0;
    while (path_index < path.len) {
        if (pattern_index < pattern.len and pattern[pattern_index] != '*' and pattern[pattern_index] == path[path_index]) {
            pattern_index += 1;
            path_index += 1;
        } else if (pattern_index < pattern.len and pattern[pattern_index] == '*') {
            star_index = pattern_index;
            pattern_index += 1;
            retry_path = path_index;
        } else if (star_index) |star| {
            pattern_index = star + 1;
            retry_path += 1;
            path_index = retry_path;
        } else {
            return false;
        }
    }
    while (pattern_index < pattern.len and pattern[pattern_index] == '*') pattern_index += 1;
    return pattern_index == pattern.len;
}

fn isWholeWord(text: []const u8, start: usize, end: usize) bool {
    const left_ok = start == 0 or !isWordChar(text[start - 1]);
    const right_ok = end == text.len or !isWordChar(text[end]);
    return left_ok and right_ok;
}

fn isWordChar(char: u8) bool {
    return std.ascii.isAlphanumeric(char) or char == '_';
}

test "search finds fixture auth helper" {
    const ws = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(ws);
    ws.* = .{};
    _ = try ws.openPath(std.testing.io, "fixtures/acme-dashboard");
    var search_bufs: SearchBuffers = .{};
    search_bufs.search(std.testing.io, ws, "createSession");
    try std.testing.expect(search_bufs.hit_count > 0);
    try std.testing.expect(std.mem.indexOf(u8, search_bufs.hits[0].path, "auth.ts") != null);
}

test "search case sensitive" {
    const ws = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(ws);
    ws.* = .{};
    _ = try ws.openPath(std.testing.io, "fixtures/acme-dashboard");
    var search_bufs: SearchBuffers = .{};
    search_bufs.searchWithOptions(std.testing.io, ws, "TODO", true);
    const case_hits = search_bufs.hit_count;
    try std.testing.expect(case_hits > 0);
    search_bufs.searchWithOptions(std.testing.io, ws, "todo", true);
    try std.testing.expect(search_bufs.hit_count < case_hits or search_bufs.hit_count == 0);
}

test "search applies whole word and bounded path scopes" {
    try std.testing.expect(pathInScope("src/server/auth.ts", "src/*", "*.test.ts"));
    try std.testing.expect(!pathInScope("tests/auth.test.ts", "src/*,*.ts", "*.test.ts"));
    try std.testing.expect(pathInScope("src/server/auth.ts", "src/", ""));
    try std.testing.expect(pathInScope("src/server/auth.ts", ".ts", ""));
    try std.testing.expect(indexMatch("cat catalog", "cat", true, true).? == 0);
    try std.testing.expect(indexMatch("catalog", "cat", true, true) == null);
}
