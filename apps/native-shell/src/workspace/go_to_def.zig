//! Heuristic Go to Definition — bounded workspace text search (no LSP).

const std = @import("std");
const workspace_store = @import("workspace_store.zig");
const scanner = @import("scanner.zig");

pub const max_hits: usize = 24;
pub const max_query: usize = 64;

pub const DefHit = struct {
    id: u32 = 0,
    file_id: u32 = 0,
    path: []const u8 = "",
    line: u32 = 0,
    preview: []const u8 = "",
};

pub const GoToDefBuffers = struct {
    hits: [max_hits]DefHit = [_]DefHit{.{}} ** max_hits,
    path_pool: [max_hits][scanner.max_rel_path_len]u8 = undefined,
    preview_pool: [max_hits][120]u8 = undefined,
    path_lens: [max_hits]usize = [_]usize{0} ** max_hits,
    preview_lens: [max_hits]usize = [_]usize{0} ** max_hits,
    count: u32 = 0,
    status: []const u8 = "idle",

    pub fn hitsSlice(self: *const GoToDefBuffers) []const DefHit {
        return self.hits[0..self.count];
    }

    pub fn clear(self: *GoToDefBuffers) void {
        self.count = 0;
        self.status = "idle";
    }

    pub fn search(self: *GoToDefBuffers, io: std.Io, ws: *workspace_store.WorkspaceBuffers, symbol: []const u8) void {
        self.clear();
        const q = std.mem.trim(u8, symbol, " \t");
        if (q.len == 0 or q.len > max_query) {
            self.status = "empty symbol";
            return;
        }
        var file_buf: [scanner.max_file_bytes]u8 = undefined;
        var i: u32 = 0;
        while (i < ws.file_node_count and self.count < max_hits) : (i += 1) {
            const node = ws.file_nodes[i];
            if (node.is_dir) continue;
            const n = scanner.readTextFile(io, ws.rootPath(), node.path, file_buf[0..]) catch continue;
            scanFile(self, node.id, node.path, file_buf[0..n], q);
        }
        self.status = if (self.count == 0) "not found" else "done";
    }

    fn scanFile(self: *GoToDefBuffers, file_id: u32, path: []const u8, text: []const u8, symbol: []const u8) void {
        var line_no: u32 = 1;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= text.len and self.count < max_hits) : (i += 1) {
            if (i == text.len or text[i] == '\n') {
                const line = text[start..i];
                if (lineLooksLikeDefinition(line, symbol)) {
                    self.push(file_id, path, line_no, line);
                }
                line_no += 1;
                start = i + 1;
            }
        }
    }

    fn push(self: *GoToDefBuffers, file_id: u32, path: []const u8, line: u32, preview: []const u8) void {
        if (self.count >= max_hits) return;
        const idx = self.count;
        const plen = @min(path.len, self.path_pool[idx].len);
        @memcpy(self.path_pool[idx][0..plen], path[0..plen]);
        self.path_lens[idx] = plen;
        const trimmed = std.mem.trim(u8, preview, " \t\r");
        const vlen = @min(trimmed.len, self.preview_pool[idx].len);
        @memcpy(self.preview_pool[idx][0..vlen], trimmed[0..vlen]);
        self.preview_lens[idx] = vlen;
        self.hits[idx] = .{
            .id = idx + 1,
            .file_id = file_id,
            .path = self.path_pool[idx][0..plen],
            .line = line,
            .preview = self.preview_pool[idx][0..vlen],
        };
        self.count += 1;
    }
};

fn lineLooksLikeDefinition(line: []const u8, symbol: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    const patterns = [_][]const u8{
        "function ",
        "export function ",
        "export default function ",
        "class ",
        "export class ",
        "const ",
        "let ",
        "var ",
        "def ",
        "async def ",
        "fn ",
        "pub fn ",
        "struct ",
        "pub struct ",
        "type ",
        "interface ",
        "enum ",
    };
    for (patterns) |p| {
        if (std.mem.startsWith(u8, t, p)) {
            const rest = t[p.len..];
            if (std.ascii.startsWithIgnoreCase(rest, symbol)) {
                const after = rest[symbol.len..];
                if (after.len == 0) return true;
                const c = after[0];
                return c == '(' or c == ' ' or c == '<' or c == ':' or c == '{' or c == '=' or c == '\t';
            }
        }
    }
    return false;
}

test "go to def finds Chart in fixture" {
    const ws = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(ws);
    ws.* = .{};
    _ = try ws.openPath(std.testing.io, "fixtures/acme-dashboard");
    var bufs: GoToDefBuffers = .{};
    bufs.search(std.testing.io, ws, "Chart");
    try std.testing.expect(bufs.count > 0);
}
