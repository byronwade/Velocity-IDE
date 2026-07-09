//! Quick Open — filter workspace file names by substring (MVP fuzzy).

const std = @import("std");
const workspace_store = @import("workspace_store.zig");
const scanner = @import("scanner.zig");

pub const max_results: usize = 48;
pub const max_query: usize = 64;

pub const QuickItem = struct {
    id: u32 = 0,
    file_id: u32 = 0,
    name: []const u8 = "",
    path: []const u8 = "",
};

pub const QuickOpenBuffers = struct {
    items: [max_results]QuickItem = [_]QuickItem{.{}} ** max_results,
    item_count: u32 = 0,
    name_pool: [max_results][scanner.max_name_len]u8 = undefined,
    path_pool: [max_results][scanner.max_rel_path_len]u8 = undefined,
    name_lens: [max_results]usize = [_]usize{0} ** max_results,
    path_lens: [max_results]usize = [_]usize{0} ** max_results,
    status: []const u8 = "idle",

    pub fn itemsSlice(self: *QuickOpenBuffers) []const QuickItem {
        return self.items[0..self.item_count];
    }

    pub fn clear(self: *QuickOpenBuffers) void {
        self.item_count = 0;
        self.status = "idle";
    }

    pub fn filter(self: *QuickOpenBuffers, ws: *workspace_store.WorkspaceBuffers, query: []const u8) void {
        self.clear();
        const q = std.mem.trim(u8, query, " \t");
        var i: u32 = 0;
        while (i < ws.file_node_count and self.item_count < max_results) : (i += 1) {
            const node = ws.file_nodes[i];
            if (node.is_dir) continue;
            if (q.len == 0 or std.ascii.indexOfIgnoreCase(node.name, q) != null or std.ascii.indexOfIgnoreCase(node.path, q) != null) {
                self.push(node.id, node.name, node.path);
            }
        }
        self.status = if (self.item_count == 0) "no files" else "done";
    }

    fn push(self: *QuickOpenBuffers, file_id: u32, name: []const u8, path: []const u8) void {
        const idx = self.item_count;
        const nlen = @min(name.len, self.name_pool[idx].len);
        @memcpy(self.name_pool[idx][0..nlen], name[0..nlen]);
        self.name_lens[idx] = nlen;
        const plen = @min(path.len, self.path_pool[idx].len);
        @memcpy(self.path_pool[idx][0..plen], path[0..plen]);
        self.path_lens[idx] = plen;
        self.items[idx] = .{
            .id = idx + 1,
            .file_id = file_id,
            .name = self.name_pool[idx][0..nlen],
            .path = self.path_pool[idx][0..plen],
        };
        self.item_count += 1;
    }
};

test "quick open filters by name" {
    const ws = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(ws);
    ws.* = .{};
    _ = try ws.openPath(std.testing.io, "fixtures/acme-dashboard");
    var q: QuickOpenBuffers = .{};
    q.filter(ws, "auth");
    try std.testing.expect(q.item_count > 0);
    try std.testing.expect(std.mem.indexOf(u8, q.items[0].path, "auth") != null);
}
