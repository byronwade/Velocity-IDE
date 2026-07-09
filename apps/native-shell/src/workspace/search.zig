//! Bounded in-workspace text search (no ripgrep process).
//! Scans already-loaded file nodes; reads up to max_file_bytes per file.

const std = @import("std");
const scanner = @import("../workspace/scanner.zig");
const workspace_store = @import("../workspace/workspace_store.zig");

pub const max_hits: usize = 64;
pub const max_query: usize = 64;
pub const max_preview: usize = 120;

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
        self.clear();
        if (query.len == 0) {
            self.status = "empty query";
            return;
        }
        self.status = "searching";
        var file_buf: [scanner.max_file_bytes]u8 = undefined;
        var i: u32 = 0;
        while (i < ws.file_node_count and self.hit_count < max_hits) : (i += 1) {
            const node = ws.file_nodes[i];
            if (node.is_dir) continue;
            const n = scanner.readTextFile(io, ws.rootPath(), node.path, file_buf[0..]) catch continue;
            self.scanFile(node.path, file_buf[0..n], query);
        }
        if (self.hit_count == 0) {
            self.status = "no matches";
        } else {
            self.status = std.fmt.bufPrint(&self.status_buf, "{d} hits", .{self.hit_count}) catch "done";
        }
    }

    fn scanFile(self: *SearchBuffers, path: []const u8, content: []const u8, query: []const u8) void {
        var line_no: u32 = 1;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= content.len and self.hit_count < max_hits) : (i += 1) {
            if (i == content.len or content[i] == '\n') {
                const line = content[start..i];
                if (std.ascii.indexOfIgnoreCase(line, query) != null) {
                    self.pushHit(path, line_no, line);
                }
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
