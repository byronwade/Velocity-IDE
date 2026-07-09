//! Lightweight "problems" scan — TODO/FIXME/HACK/XXX markers in workspace files.
//! Not a real linter; gives developers a familiar Problems panel without LSP.

const std = @import("std");
const scanner = @import("scanner.zig");
const workspace_store = @import("workspace_store.zig");

pub const max_problems: usize = 64;
pub const max_preview: usize = 100;

pub const Severity = enum { info, warning };

pub const Problem = struct {
    id: u32 = 0,
    path: []const u8 = "",
    line: u32 = 0,
    kind: []const u8 = "",
    preview: []const u8 = "",
};

pub const ProblemBuffers = struct {
    items: [max_problems]Problem = [_]Problem{.{}} ** max_problems,
    item_count: u32 = 0,
    path_pool: [max_problems][scanner.max_rel_path_len]u8 = undefined,
    path_lens: [max_problems]usize = [_]usize{0} ** max_problems,
    preview_pool: [max_problems][max_preview]u8 = undefined,
    preview_lens: [max_problems]usize = [_]usize{0} ** max_problems,
    kind_pool: [max_problems][8]u8 = undefined,
    kind_lens: [max_problems]usize = [_]usize{0} ** max_problems,
    status: []const u8 = "idle",
    status_buf: [48]u8 = undefined,

    pub fn itemsSlice(self: *ProblemBuffers) []const Problem {
        return self.items[0..self.item_count];
    }

    pub fn clear(self: *ProblemBuffers) void {
        self.item_count = 0;
        self.status = "idle";
    }

    pub fn scan(self: *ProblemBuffers, io: std.Io, ws: *workspace_store.WorkspaceBuffers) void {
        self.clear();
        self.status = "scanning";
        var file_buf: [scanner.max_file_bytes]u8 = undefined;
        var i: u32 = 0;
        while (i < ws.file_node_count and self.item_count < max_problems) : (i += 1) {
            const node = ws.file_nodes[i];
            if (node.is_dir) continue;
            const n = scanner.readTextFile(io, ws.rootPath(), node.path, file_buf[0..]) catch continue;
            self.scanFile(node.path, file_buf[0..n]);
        }
        if (self.item_count == 0) {
            self.status = "no markers";
        } else {
            self.status = std.fmt.bufPrint(&self.status_buf, "{d} markers", .{self.item_count}) catch "done";
        }
    }

    pub fn scanFile(self: *ProblemBuffers, path: []const u8, content: []const u8) void {
        var line_no: u32 = 1;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= content.len and self.item_count < max_problems) : (i += 1) {
            if (i == content.len or content[i] == '\n') {
                const line = content[start..i];
                if (markerInLine(line)) |kind| {
                    self.push(path, line_no, kind, line);
                }
                line_no += 1;
                start = i + 1;
            }
        }
    }

    fn markerInLine(line: []const u8) ?[]const u8 {
        const markers = [_][]const u8{ "TODO", "FIXME", "HACK", "XXX" };
        for (markers) |m| {
            if (std.ascii.indexOfIgnoreCase(line, m) != null) return m;
        }
        return null;
    }

    fn push(self: *ProblemBuffers, path: []const u8, line: u32, kind: []const u8, preview_src: []const u8) void {
        const idx = self.item_count;
        const plen = @min(path.len, self.path_pool[idx].len);
        @memcpy(self.path_pool[idx][0..plen], path[0..plen]);
        self.path_lens[idx] = plen;
        const klen = @min(kind.len, self.kind_pool[idx].len);
        @memcpy(self.kind_pool[idx][0..klen], kind[0..klen]);
        self.kind_lens[idx] = klen;
        const trimmed = std.mem.trim(u8, preview_src, " \t\r");
        const vlen = @min(trimmed.len, self.preview_pool[idx].len);
        @memcpy(self.preview_pool[idx][0..vlen], trimmed[0..vlen]);
        self.preview_lens[idx] = vlen;
        self.items[idx] = .{
            .id = idx + 1,
            .path = self.path_pool[idx][0..plen],
            .line = line,
            .kind = self.kind_pool[idx][0..klen],
            .preview = self.preview_pool[idx][0..vlen],
        };
        self.item_count += 1;
    }
};

test "problems finds TODO marker" {
    var p: ProblemBuffers = .{};
    // Direct scanFile via temporary content through push path
    p.scanFile("src/a.ts", "const x = 1;\n// TODO: wire this\n");
    try std.testing.expect(p.item_count == 1);
    try std.testing.expectEqualStrings("TODO", p.items[0].kind);
    try std.testing.expect(p.items[0].line == 2);
}
