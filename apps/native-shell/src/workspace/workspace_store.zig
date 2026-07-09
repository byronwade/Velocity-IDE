//! Workspace store — open folder, bounded tree, document text.
//! Lazy: only runs on explicit open. Skips node_modules/.git/vendor.

const std = @import("std");
const scanner = @import("scanner.zig");

pub const max_nodes = scanner.max_nodes;
pub const max_open_tabs: usize = 8;
pub const max_editor_bytes = scanner.max_file_bytes;
pub const max_root_path_len = scanner.max_root_path_len;

pub const FileNode = struct {
    id: u32 = 0,
    name: []const u8 = "",
    path: []const u8 = "",
    depth: u8 = 0,
    is_dir: bool = false,
};

pub const Tab = struct {
    id: u32 = 0,
    title: []const u8 = "",
    path: []const u8 = "",
    language: []const u8 = "",
    dirty: bool = false,
};

pub const Workspace = struct {
    open: bool = false,
    trusted: bool = false,
    name: []const u8 = "",
    branch: []const u8 = "main",
    root_path: []const u8 = "",
    node_count: u32 = 0,
    scan_error: []const u8 = "",
    from_disk: bool = false,
};

/// Owned buffers for one workspace session (lives on Model).
pub const WorkspaceBuffers = struct {
    root_path_buf: [max_root_path_len]u8 = undefined,
    root_path_len: usize = 0,
    name_buf: [64]u8 = undefined,
    name_len: usize = 0,

    scan_nodes: [max_nodes]scanner.ScanNode = undefined,
    name_pool: [16 * 1024]u8 = undefined,
    path_pool: [48 * 1024]u8 = undefined,
    scan_name_used: u32 = 0,
    scan_path_used: u32 = 0,
    scan_count: u32 = 0,

    /// Materialized FileNode views pointing into pools.
    file_nodes: [max_nodes]FileNode = [_]FileNode{.{}} ** max_nodes,
    file_node_count: u32 = 0,

    tabs: [max_open_tabs]Tab = [_]Tab{.{}} ** max_open_tabs,
    tab_count: u32 = 0,
    /// Path storage for tabs (copies from path pool / paths).
    tab_path_pool: [max_open_tabs][scanner.max_rel_path_len]u8 = undefined,
    tab_path_lens: [max_open_tabs]usize = [_]usize{0} ** max_open_tabs,
    tab_title_pool: [max_open_tabs][scanner.max_name_len]u8 = undefined,
    tab_title_lens: [max_open_tabs]usize = [_]usize{0} ** max_open_tabs,

    editor_buf: [max_editor_bytes]u8 = undefined,
    editor_len: usize = 0,
    editor_path_buf: [scanner.max_rel_path_len]u8 = undefined,
    editor_path_len: usize = 0,
    editor_truncated: bool = false,

    pub fn rootPath(self: *const WorkspaceBuffers) []const u8 {
        return self.root_path_buf[0..self.root_path_len];
    }

    pub fn projectName(self: *const WorkspaceBuffers) []const u8 {
        return self.name_buf[0..self.name_len];
    }

    pub fn fileNodesSlice(self: *WorkspaceBuffers) []const FileNode {
        return self.file_nodes[0..self.file_node_count];
    }

    pub fn tabsSlice(self: *WorkspaceBuffers) []const Tab {
        return self.tabs[0..self.tab_count];
    }

    pub fn editorText(self: *const WorkspaceBuffers) []const u8 {
        if (self.editor_truncated) return "// Binary or unsupported file";
        return self.editor_buf[0..self.editor_len];
    }

    pub fn editorPath(self: *const WorkspaceBuffers) []const u8 {
        return self.editor_path_buf[0..self.editor_path_len];
    }

    pub fn setEditorText(self: *WorkspaceBuffers, text: []const u8) void {
        const n = @min(text.len, self.editor_buf.len);
        @memcpy(self.editor_buf[0..n], text[0..n]);
        self.editor_len = n;
        self.editor_truncated = false;
    }

    pub fn saveActiveFile(self: *WorkspaceBuffers, io: std.Io, text: []const u8) !void {
        const rel = self.editorPath();
        if (rel.len == 0) return error.NotFound;
        try scanner.writeTextFile(io, self.rootPath(), rel, text);
        self.setEditorText(text);
    }

    /// Create a new relative file (empty or with seed text), rescan, and open it.
    pub fn createFile(self: *WorkspaceBuffers, io: std.Io, rel_path: []const u8, seed: []const u8) !u32 {
        if (rel_path.len == 0) return error.NotFound;
        if (std.mem.indexOfScalar(u8, rel_path, 0) != null) return error.NotFound;
        try scanner.writeTextFile(io, self.rootPath(), rel_path, seed);
        // Rescan so the tree includes the new file.
        const root = self.rootPath();
        var root_copy: [max_root_path_len]u8 = undefined;
        if (root.len > root_copy.len) return error.PathTooLong;
        @memcpy(root_copy[0..root.len], root);
        _ = try self.openPath(io, root_copy[0..root.len]);
        if (self.findNodeByPath(rel_path)) |node| {
            try self.openFileById(io, node.id);
            return node.id;
        }
        return error.NotFound;
    }

    pub fn deleteFileById(self: *WorkspaceBuffers, io: std.Io, id: u32) !void {
        const node = self.findNode(id) orelse return error.NotFound;
        if (node.is_dir) return error.NotFound;
        try scanner.deleteRelFile(io, self.rootPath(), node.path);
        const root = self.rootPath();
        var root_copy: [max_root_path_len]u8 = undefined;
        if (root.len > root_copy.len) return error.PathTooLong;
        @memcpy(root_copy[0..root.len], root);
        _ = try self.openPath(io, root_copy[0..root.len]);
    }

    pub fn renameFileById(self: *WorkspaceBuffers, io: std.Io, id: u32, new_rel: []const u8) !u32 {
        const node = self.findNode(id) orelse return error.NotFound;
        if (node.is_dir) return error.NotFound;
        if (new_rel.len == 0) return error.NotFound;
        try scanner.renameRelFile(io, self.rootPath(), node.path, new_rel);
        const root = self.rootPath();
        var root_copy: [max_root_path_len]u8 = undefined;
        if (root.len > root_copy.len) return error.PathTooLong;
        @memcpy(root_copy[0..root.len], root);
        _ = try self.openPath(io, root_copy[0..root.len]);
        if (self.findNodeByPath(new_rel)) |n| {
            try self.openFileById(io, n.id);
            return n.id;
        }
        return error.NotFound;
    }

    pub fn clear(self: *WorkspaceBuffers) void {
        self.* = .{};
    }

    fn setRoot(self: *WorkspaceBuffers, path: []const u8) !void {
        if (path.len == 0 or path.len > max_root_path_len) return error.PathTooLong;
        @memcpy(self.root_path_buf[0..path.len], path);
        self.root_path_len = path.len;
        const base = scanner.baseName(path);
        const nlen = @min(base.len, self.name_buf.len);
        @memcpy(self.name_buf[0..nlen], base[0..nlen]);
        self.name_len = nlen;
    }

    fn rebuildFileNodes(self: *WorkspaceBuffers) void {
        var bufs = scanner.ScanBuffers{
            .nodes = self.scan_nodes[0..],
            .name_pool = self.name_pool[0..],
            .path_pool = self.path_pool[0..],
            .node_count = self.scan_count,
            .name_used = self.scan_name_used,
            .path_used = self.scan_path_used,
        };
        self.file_node_count = self.scan_count;
        var i: u32 = 0;
        while (i < self.scan_count) : (i += 1) {
            const sn = self.scan_nodes[i];
            self.file_nodes[i] = .{
                .id = sn.id,
                .name = scanner.nodeName(&bufs, sn),
                .path = scanner.nodePath(&bufs, sn),
                .depth = sn.depth,
                .is_dir = sn.is_dir,
            };
        }
    }

    pub fn openPath(self: *WorkspaceBuffers, io: std.Io, path: []const u8) !Workspace {
        self.clear();
        try self.setRoot(path);

        var bufs = scanner.ScanBuffers{
            .nodes = self.scan_nodes[0..],
            .name_pool = self.name_pool[0..],
            .path_pool = self.path_pool[0..],
        };
        const count = scanner.scanWorkspace(io, path, &bufs) catch |err| {
            return Workspace{
                .open = true,
                .name = self.projectName(),
                .root_path = self.rootPath(),
                .from_disk = true,
                .scan_error = switch (err) {
                    error.NotDir => "Not a directory",
                    error.AccessDenied => "Access denied",
                    error.TooManyNodes => "Too many files (cap 256)",
                    else => "Scan failed",
                },
            };
        };
        self.scan_count = count;
        self.scan_name_used = bufs.name_used;
        self.scan_path_used = bufs.path_used;
        self.rebuildFileNodes();

        // Open first text file as a tab if present.
        var i: u32 = 0;
        while (i < self.file_node_count) : (i += 1) {
            const n = self.file_nodes[i];
            if (!n.is_dir) {
                _ = self.openFileById(io, n.id) catch {};
                break;
            }
        }

        return .{
            .open = true,
            .trusted = false,
            .name = self.projectName(),
            .branch = "main",
            .root_path = self.rootPath(),
            .node_count = self.file_node_count,
            .from_disk = true,
            .scan_error = "",
        };
    }

    pub fn findNode(self: *const WorkspaceBuffers, id: u32) ?FileNode {
        for (self.file_nodes[0..self.file_node_count]) |n| {
            if (n.id == id) return n;
        }
        return null;
    }

    pub fn findNodeByPath(self: *const WorkspaceBuffers, path: []const u8) ?FileNode {
        for (self.file_nodes[0..self.file_node_count]) |n| {
            if (std.mem.eql(u8, n.path, path)) return n;
        }
        return null;
    }

    pub fn closeTab(self: *WorkspaceBuffers, id: u32) void {
        var i: u32 = 0;
        while (i < self.tab_count) : (i += 1) {
            if (self.tabs[i].id == id) {
                var j = i;
                while (j + 1 < self.tab_count) : (j += 1) {
                    self.tabs[j] = self.tabs[j + 1];
                    self.tab_path_lens[j] = self.tab_path_lens[j + 1];
                    self.tab_title_lens[j] = self.tab_title_lens[j + 1];
                    @memcpy(self.tab_path_pool[j][0..self.tab_path_lens[j]], self.tab_path_pool[j + 1][0..self.tab_path_lens[j]]);
                    @memcpy(self.tab_title_pool[j][0..self.tab_title_lens[j]], self.tab_title_pool[j + 1][0..self.tab_title_lens[j]]);
                    // Re-bind slices after move
                    self.tabs[j].path = self.tab_path_pool[j][0..self.tab_path_lens[j]];
                    self.tabs[j].title = self.tab_title_pool[j][0..self.tab_title_lens[j]];
                }
                self.tab_count -= 1;
                return;
            }
        }
    }

    pub fn openFileById(self: *WorkspaceBuffers, io: std.Io, id: u32) !void {
        const node = self.findNode(id) orelse return error.NotFound;
        if (node.is_dir) return;

        // Copy path into editor path buf
        if (node.path.len > self.editor_path_buf.len) return error.PathTooLong;
        @memcpy(self.editor_path_buf[0..node.path.len], node.path);
        self.editor_path_len = node.path.len;
        self.editor_truncated = false;
        self.editor_len = 0;

        const n = scanner.readTextFile(io, self.rootPath(), node.path, self.editor_buf[0..]) catch |err| {
            if (err == error.BinaryFile) {
                self.editor_truncated = true;
                self.editor_len = 0;
            } else {
                const msg = "Unable to read file";
                @memcpy(self.editor_buf[0..msg.len], msg);
                self.editor_len = msg.len;
            }
            try self.ensureTab(node);
            return;
        };
        self.editor_len = n;
        try self.ensureTab(node);
    }

    fn ensureTab(self: *WorkspaceBuffers, node: FileNode) !void {
        // Reuse existing tab for path
        var i: u32 = 0;
        while (i < self.tab_count) : (i += 1) {
            if (std.mem.eql(u8, self.tabs[i].path, node.path)) {
                return;
            }
        }
        if (self.tab_count >= max_open_tabs) {
            // Drop oldest
            var j: u32 = 0;
            while (j + 1 < self.tab_count) : (j += 1) {
                self.tabs[j] = self.tabs[j + 1];
                self.tab_path_lens[j] = self.tab_path_lens[j + 1];
                self.tab_title_lens[j] = self.tab_title_lens[j + 1];
                @memcpy(self.tab_path_pool[j][0..self.tab_path_lens[j]], self.tab_path_pool[j + 1][0..self.tab_path_lens[j]]);
                @memcpy(self.tab_title_pool[j][0..self.tab_title_lens[j]], self.tab_title_pool[j + 1][0..self.tab_title_lens[j]]);
            }
            self.tab_count -= 1;
        }
        const idx = self.tab_count;
        const plen = @min(node.path.len, self.tab_path_pool[idx].len);
        @memcpy(self.tab_path_pool[idx][0..plen], node.path[0..plen]);
        self.tab_path_lens[idx] = plen;
        const title = scanner.baseName(node.path);
        const tlen = @min(title.len, self.tab_title_pool[idx].len);
        @memcpy(self.tab_title_pool[idx][0..tlen], title[0..tlen]);
        self.tab_title_lens[idx] = tlen;
        self.tabs[idx] = .{
            .id = node.id,
            .title = self.tab_title_pool[idx][0..tlen],
            .path = self.tab_path_pool[idx][0..plen],
            .language = scanner.languageForPath(node.path),
            .dirty = false,
        };
        self.tab_count += 1;
    }
};

/// Resolve a known project key to a relative fixture path (dev/demo).
pub fn scannerLanguage(path: []const u8) []const u8 {
    return scanner.languageForPath(path);
}

pub fn fixturePathForKey(key: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, key, "acme-dashboard") or std.mem.eql(u8, key, "fixture") or std.mem.eql(u8, key, "open_folder")) {
        return "fixtures/acme-dashboard";
    }
    return null;
}

test "scan fixture skips node_modules" {
    const bufs = try std.testing.allocator.create(WorkspaceBuffers);
    defer std.testing.allocator.destroy(bufs);
    bufs.* = .{};
    const ws = try bufs.openPath(std.testing.io, "fixtures/acme-dashboard");
    try std.testing.expect(ws.from_disk);
    try std.testing.expect(ws.node_count > 0);
    for (bufs.file_nodes[0..bufs.file_node_count]) |n| {
        try std.testing.expect(!std.mem.eql(u8, n.name, "node_modules"));
        try std.testing.expect(!std.mem.eql(u8, n.name, ".git"));
        try std.testing.expect(!std.mem.startsWith(u8, n.path, "node_modules/"));
    }
}
