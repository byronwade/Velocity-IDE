//! Workspace store — open folder, bounded tree, document text.
//! Lazy: only runs on explicit open. Skips node_modules/.git/vendor.

const std = @import("std");
const scanner = @import("scanner.zig");
const file_fingerprint = @import("file_fingerprint.zig");

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
    /// Visual indent spacer for the explorer tree (spaces, not a depth digit).
    indent: []const u8 = "",
    /// Folder/file marker shown before the name (`>` dir, `·` file).
    kind_mark: []const u8 = "",
};

const indent_steps = [_][]const u8{
    "",
    "  ",
    "    ",
    "      ",
    "        ",
    "          ",
    "            ",
    "              ",
    "                ",
};

pub fn decorateFileNode(node: FileNode) FileNode {
    var out = node;
    out.indent = indent_steps[@min(node.depth, indent_steps.len - 1)];
    out.kind_mark = if (node.is_dir) ">" else "-";
    return out;
}

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
    /// Bounded in-memory working copies. This prevents tab switches from dropping edits.
    tab_text_pool: [max_open_tabs][max_editor_bytes]u8 = undefined,
    tab_text_lens: [max_open_tabs]usize = [_]usize{0} ** max_open_tabs,
    tab_text_loaded: [max_open_tabs]bool = [_]bool{false} ** max_open_tabs,
    tab_disk_fingerprints: [max_open_tabs]file_fingerprint.Fingerprint = [_]file_fingerprint.Fingerprint{.{}} ** max_open_tabs,

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

    pub fn cacheActiveText(self: *WorkspaceBuffers, text: []const u8) void {
        const idx = self.activeTabIndex() orelse return;
        const n = @min(text.len, self.tab_text_pool[idx].len);
        @memcpy(self.tab_text_pool[idx][0..n], text[0..n]);
        self.tab_text_lens[idx] = n;
        self.tab_text_loaded[idx] = true;
        self.setEditorText(text);
    }

    pub fn activeTabDirty(self: *const WorkspaceBuffers) bool {
        const idx = self.activeTabIndex() orelse return false;
        return self.tabs[idx].dirty;
    }

    pub fn tabIsDirty(self: *const WorkspaceBuffers, id: u32) bool {
        const idx = self.tabIndexById(id) orelse return false;
        return self.tabs[idx].dirty;
    }

    pub fn saveActiveFile(self: *WorkspaceBuffers, io: std.Io, text: []const u8) !void {
        if (self.activeFileChanged(io)) return error.FileChanged;
        try self.saveActiveFileForce(io, text);
    }

    pub fn saveActiveFileForce(self: *WorkspaceBuffers, io: std.Io, text: []const u8) !void {
        const rel = self.editorPath();
        if (rel.len == 0) return error.NotFound;
        try scanner.writeTextFile(io, self.rootPath(), rel, text);
        self.cacheActiveText(text);
        if (self.activeTabIndex()) |idx| {
            self.tab_disk_fingerprints[idx] = file_fingerprint.ofBytes(text);
        }
    }

    pub fn activeFileChanged(self: *const WorkspaceBuffers, io: std.Io) bool {
        const idx = self.activeTabIndex() orelse return false;
        return file_fingerprint.changed(
            io,
            self.rootPath(),
            self.tabs[idx].path,
            self.tab_disk_fingerprints[idx],
        );
    }

    pub fn saveTabById(self: *WorkspaceBuffers, io: std.Io, id: u32) !void {
        const idx = self.tabIndexById(id) orelse return error.NotFound;
        if (!self.tab_text_loaded[idx]) return error.NotFound;
        if (file_fingerprint.changed(
            io,
            self.rootPath(),
            self.tabs[idx].path,
            self.tab_disk_fingerprints[idx],
        )) return error.FileChanged;
        try scanner.writeTextFile(
            io,
            self.rootPath(),
            self.tabs[idx].path,
            self.tab_text_pool[idx][0..self.tab_text_lens[idx]],
        );
        self.tab_disk_fingerprints[idx] = file_fingerprint.ofBytes(
            self.tab_text_pool[idx][0..self.tab_text_lens[idx]],
        );
        self.setTabDirty(id, false);
    }

    /// Rescan the workspace tree while preserving open tabs (matched by path).
    /// Returns the new node id for `active_path` when found, else 0.
    /// Caller is responsible for re-applying an unsaved document buffer.
    pub fn rescanPreserveTabs(self: *WorkspaceBuffers, io: std.Io, active_path: []const u8) !u32 {
        const root = self.rootPath();
        if (root.len == 0) return error.NotFound;

        var saved_paths: [max_open_tabs][scanner.max_rel_path_len]u8 = undefined;
        var saved_lens: [max_open_tabs]usize = [_]usize{0} ** max_open_tabs;
        var saved_dirty: [max_open_tabs]bool = [_]bool{false} ** max_open_tabs;
        var saved_text: [max_open_tabs][max_editor_bytes]u8 = undefined;
        var saved_text_lens: [max_open_tabs]usize = [_]usize{0} ** max_open_tabs;
        var saved_fingerprints: [max_open_tabs]file_fingerprint.Fingerprint = [_]file_fingerprint.Fingerprint{.{}} ** max_open_tabs;
        var saved_count: u32 = 0;
        for (self.tabsSlice(), 0..) |tab, source_idx| {
            if (saved_count >= max_open_tabs) break;
            const n = @min(tab.path.len, saved_paths[saved_count].len);
            @memcpy(saved_paths[saved_count][0..n], tab.path[0..n]);
            saved_lens[saved_count] = n;
            saved_dirty[saved_count] = tab.dirty;
            if (tab.dirty) {
                const text_len = self.tab_text_lens[source_idx];
                @memcpy(saved_text[saved_count][0..text_len], self.tab_text_pool[source_idx][0..text_len]);
                saved_text_lens[saved_count] = text_len;
                saved_fingerprints[saved_count] = self.tab_disk_fingerprints[source_idx];
            }
            saved_count += 1;
        }

        var root_copy: [max_root_path_len]u8 = undefined;
        if (root.len > root_copy.len) return error.PathTooLong;
        @memcpy(root_copy[0..root.len], root);
        const root_slice = root_copy[0..root.len];

        // Rescan tree only — do not use openPath (it clears tabs and auto-opens first file).
        var bufs = scanner.ScanBuffers{
            .nodes = self.scan_nodes[0..],
            .name_pool = self.name_pool[0..],
            .path_pool = self.path_pool[0..],
        };
        const count = try scanner.scanWorkspace(io, root_slice, &bufs);
        self.scan_count = count;
        self.scan_name_used = bufs.name_used;
        self.scan_path_used = bufs.path_used;
        self.tab_count = 0;
        self.editor_len = 0;
        self.editor_path_len = 0;
        self.editor_truncated = false;
        self.rebuildFileNodes();

        var i: u32 = 0;
        while (i < saved_count) : (i += 1) {
            const path = saved_paths[i][0..saved_lens[i]];
            if (self.findNodeByPath(path)) |node| {
                self.openFileById(io, node.id) catch continue;
                if (saved_dirty[i]) {
                    self.cacheActiveText(saved_text[i][0..saved_text_lens[i]]);
                    if (self.activeTabIndex()) |idx| self.tab_disk_fingerprints[idx] = saved_fingerprints[i];
                    self.setTabDirty(node.id, true);
                }
            }
        }

        if (active_path.len > 0) {
            if (self.findNodeByPath(active_path)) |node| {
                self.openFileById(io, node.id) catch {};
                return node.id;
            }
        }
        if (self.tab_count > 0) {
            self.openFileById(io, self.tabs[0].id) catch {};
            return self.tabs[0].id;
        }
        return 0;
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

    /// Create a relative directory, rescan, return the new node id.
    pub fn createFolder(self: *WorkspaceBuffers, io: std.Io, rel_path: []const u8) !u32 {
        if (rel_path.len == 0) return error.NotFound;
        try scanner.createRelDir(io, self.rootPath(), rel_path);
        const root = self.rootPath();
        var root_copy: [max_root_path_len]u8 = undefined;
        if (root.len > root_copy.len) return error.PathTooLong;
        @memcpy(root_copy[0..root.len], root);
        _ = try self.openPath(io, root_copy[0..root.len]);
        if (self.findNodeByPath(rel_path)) |node| return node.id;
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
            self.file_nodes[i] = decorateFileNode(.{
                .id = sn.id,
                .name = scanner.nodeName(&bufs, sn),
                .path = scanner.nodePath(&bufs, sn),
                .depth = sn.depth,
                .is_dir = sn.is_dir,
            });
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
                self.removeTabAt(i);
                return;
            }
        }
    }

    pub fn openFileById(self: *WorkspaceBuffers, io: std.Io, id: u32) !void {
        const node = self.findNode(id) orelse return error.NotFound;
        if (node.is_dir) return;
        const idx = try self.ensureTab(node);

        // Copy path into editor path buf
        if (node.path.len > self.editor_path_buf.len) return error.PathTooLong;
        @memcpy(self.editor_path_buf[0..node.path.len], node.path);
        self.editor_path_len = node.path.len;
        self.editor_truncated = false;
        self.editor_len = 0;

        if (self.tab_text_loaded[idx]) {
            self.setEditorText(self.tab_text_pool[idx][0..self.tab_text_lens[idx]]);
            return;
        }

        const n = scanner.readTextFile(io, self.rootPath(), node.path, self.editor_buf[0..]) catch |err| {
            if (err == error.BinaryFile) {
                self.editor_truncated = true;
                self.editor_len = 0;
            } else {
                const msg = "Unable to read file";
                @memcpy(self.editor_buf[0..msg.len], msg);
                self.editor_len = msg.len;
            }
            self.tab_text_loaded[idx] = false;
            return;
        };
        self.editor_len = n;
        @memcpy(self.tab_text_pool[idx][0..n], self.editor_buf[0..n]);
        self.tab_text_lens[idx] = n;
        self.tab_text_loaded[idx] = true;
        self.tab_disk_fingerprints[idx] = file_fingerprint.ofBytes(self.editor_buf[0..n]);
    }

    pub fn reloadFileById(self: *WorkspaceBuffers, io: std.Io, id: u32) !void {
        if (self.tabIndexById(id)) |idx| self.tab_text_loaded[idx] = false;
        try self.openFileById(io, id);
        self.setTabDirty(id, false);
    }

    pub fn setTabDirty(self: *WorkspaceBuffers, id: u32, dirty: bool) void {
        var i: u32 = 0;
        while (i < self.tab_count) : (i += 1) {
            if (self.tabs[i].id == id) {
                self.tabs[i].dirty = dirty;
                const base = scanner.baseName(self.tabs[i].path);
                if (dirty) {
                    const suffix = " *";
                    const max_t = self.tab_title_pool[i].len;
                    const blen = @min(base.len, if (max_t > suffix.len) max_t - suffix.len else max_t);
                    @memcpy(self.tab_title_pool[i][0..blen], base[0..blen]);
                    if (blen + suffix.len <= max_t) {
                        @memcpy(self.tab_title_pool[i][blen..][0..suffix.len], suffix);
                        self.tab_title_lens[i] = blen + suffix.len;
                    } else {
                        self.tab_title_lens[i] = blen;
                    }
                } else {
                    const tlen = @min(base.len, self.tab_title_pool[i].len);
                    @memcpy(self.tab_title_pool[i][0..tlen], base[0..tlen]);
                    self.tab_title_lens[i] = tlen;
                }
                self.tabs[i].title = self.tab_title_pool[i][0..self.tab_title_lens[i]];
                return;
            }
        }
    }

    fn ensureTab(self: *WorkspaceBuffers, node: FileNode) !usize {
        // Reuse existing tab for path
        var i: u32 = 0;
        while (i < self.tab_count) : (i += 1) {
            if (std.mem.eql(u8, self.tabs[i].path, node.path)) {
                return i;
            }
        }
        if (self.tab_count >= max_open_tabs) {
            var clean_idx: ?usize = null;
            for (self.tabs[0..self.tab_count], 0..) |tab, tab_idx| {
                if (!tab.dirty) {
                    clean_idx = tab_idx;
                    break;
                }
            }
            self.removeTabAt(clean_idx orelse return error.AllTabsDirty);
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
        self.tab_text_lens[idx] = 0;
        self.tab_text_loaded[idx] = false;
        self.tab_disk_fingerprints[idx] = .{};
        self.tab_count += 1;
        return idx;
    }

    fn removeTabAt(self: *WorkspaceBuffers, index: usize) void {
        var j = index;
        while (j + 1 < self.tab_count) : (j += 1) {
            self.tabs[j] = self.tabs[j + 1];
            self.tab_path_lens[j] = self.tab_path_lens[j + 1];
            self.tab_title_lens[j] = self.tab_title_lens[j + 1];
            self.tab_text_lens[j] = self.tab_text_lens[j + 1];
            self.tab_text_loaded[j] = self.tab_text_loaded[j + 1];
            self.tab_disk_fingerprints[j] = self.tab_disk_fingerprints[j + 1];
            @memcpy(self.tab_path_pool[j][0..self.tab_path_lens[j]], self.tab_path_pool[j + 1][0..self.tab_path_lens[j]]);
            @memcpy(self.tab_title_pool[j][0..self.tab_title_lens[j]], self.tab_title_pool[j + 1][0..self.tab_title_lens[j]]);
            @memcpy(self.tab_text_pool[j][0..self.tab_text_lens[j]], self.tab_text_pool[j + 1][0..self.tab_text_lens[j]]);
            self.tabs[j].path = self.tab_path_pool[j][0..self.tab_path_lens[j]];
            self.tabs[j].title = self.tab_title_pool[j][0..self.tab_title_lens[j]];
        }
        self.tab_count -= 1;
    }

    fn activeTabIndex(self: *const WorkspaceBuffers) ?usize {
        const path = self.editorPath();
        if (path.len == 0) return null;
        var i: usize = 0;
        while (i < self.tab_count) : (i += 1) {
            if (std.mem.eql(u8, self.tabs[i].path, path)) return i;
        }
        return null;
    }

    fn tabIndexById(self: *const WorkspaceBuffers, id: u32) ?usize {
        var i: usize = 0;
        while (i < self.tab_count) : (i += 1) {
            if (self.tabs[i].id == id) return i;
        }
        return null;
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

test "tab working copies survive switches and save independently" {
    const root = "zig-out/test-tab-working-copies";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a disk\n" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/b.txt", .data = "b disk\n" });

    const ws = try std.testing.allocator.create(WorkspaceBuffers);
    defer std.testing.allocator.destroy(ws);
    ws.* = .{};
    _ = try ws.openPath(std.testing.io, root);
    const a = ws.findNodeByPath("a.txt").?;
    const b = ws.findNodeByPath("b.txt").?;

    try ws.openFileById(std.testing.io, a.id);
    ws.cacheActiveText("a edited\n");
    ws.setTabDirty(a.id, true);
    try ws.openFileById(std.testing.io, b.id);
    ws.cacheActiveText("b edited\n");
    ws.setTabDirty(b.id, true);
    try ws.openFileById(std.testing.io, a.id);
    try std.testing.expectEqualStrings("a edited\n", ws.editorText());
    try std.testing.expect(ws.activeTabDirty());

    try ws.saveTabById(std.testing.io, a.id);
    try ws.saveTabById(std.testing.io, b.id);
    var out: [32]u8 = undefined;
    const a_disk = try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out);
    try std.testing.expectEqualStrings("a edited\n", a_disk);
    const b_disk = try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/b.txt", &out);
    try std.testing.expectEqualStrings("b edited\n", b_disk);
}

test "tab overflow evicts oldest clean tab and rescan keeps shifted dirty text" {
    const root = "zig-out/test-tab-clean-eviction";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    const names = [_][]const u8{
        "a.txt", "b.txt", "c.txt", "d.txt", "e.txt",
        "f.txt", "g.txt", "h.txt", "i.txt",
    };
    for (names) |name| {
        var path_buf: [128]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ root, name });
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = name });
    }

    const ws = try std.testing.allocator.create(WorkspaceBuffers);
    defer std.testing.allocator.destroy(ws);
    ws.* = .{};
    _ = try ws.openPath(std.testing.io, root);

    const b = ws.findNodeByPath("b.txt").?;
    try ws.openFileById(std.testing.io, b.id);
    ws.cacheActiveText("dirty b working copy");
    ws.setTabDirty(b.id, true);
    for (names[2..8]) |name| {
        try ws.openFileById(std.testing.io, ws.findNodeByPath(name).?.id);
    }
    try std.testing.expectEqual(max_open_tabs, ws.tabsSlice().len);

    const i = ws.findNodeByPath("i.txt").?;
    try ws.openFileById(std.testing.io, i.id);
    try std.testing.expect(ws.findNodeByPath("a.txt") != null);
    try std.testing.expect(ws.tabIndexById(ws.findNodeByPath("a.txt").?.id) == null);
    try std.testing.expectEqualStrings("b.txt", ws.tabs[0].path);
    try std.testing.expect(ws.tabs[0].dirty);

    _ = try ws.rescanPreserveTabs(std.testing.io, "i.txt");
    const rescanned_b = ws.findNodeByPath("b.txt").?;
    try ws.openFileById(std.testing.io, rescanned_b.id);
    try std.testing.expectEqualStrings("dirty b working copy", ws.editorText());
    try std.testing.expect(ws.activeTabDirty());
}

test "tab overflow returns AllTabsDirty without changing active editor" {
    const ws = try std.testing.allocator.create(WorkspaceBuffers);
    defer std.testing.allocator.destroy(ws);
    ws.* = .{};

    var path_storage: [max_open_tabs][8]u8 = undefined;
    var i: usize = 0;
    while (i < max_open_tabs) : (i += 1) {
        const path = try std.fmt.bufPrint(&path_storage[i], "{d}.txt", .{i});
        const idx = try ws.ensureTab(.{ .id = @intCast(i + 1), .path = path });
        ws.tabs[idx].dirty = true;
    }
    @memcpy(ws.editor_path_buf[0..5], "0.txt");
    ws.editor_path_len = 5;
    ws.setEditorText("unchanged");

    try std.testing.expectError(
        error.AllTabsDirty,
        ws.ensureTab(.{ .id = 99, .path = "new.txt" }),
    );
    try std.testing.expectEqual(max_open_tabs, ws.tabsSlice().len);
    try std.testing.expectEqualStrings("0.txt", ws.editorPath());
    try std.testing.expectEqualStrings("unchanged", ws.editorText());
}
