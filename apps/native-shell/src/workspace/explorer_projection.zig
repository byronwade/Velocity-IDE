//! Bounded, path-keyed explorer collapse state and visible-tree projection.

const std = @import("std");
const scanner = @import("scanner.zig");
const workspace_store = @import("workspace_store.zig");
const git_status = @import("../scm/git_status.zig");

pub const max_collapsed = scanner.max_nodes;

pub const CollapseStore = struct {
    paths: [max_collapsed][scanner.max_rel_path_len]u8 = undefined,
    path_lens: [max_collapsed]u16 = [_]u16{0} ** max_collapsed,
    count: u16 = 0,

    pub fn clear(self: *CollapseStore) void {
        self.count = 0;
    }

    pub fn contains(self: *const CollapseStore, path: []const u8) bool {
        for (0..self.count) |index| {
            if (std.mem.eql(u8, self.paths[index][0..self.path_lens[index]], path)) return true;
        }
        return false;
    }

    pub fn toggle(self: *CollapseStore, path: []const u8) void {
        for (0..self.count) |index| {
            if (!std.mem.eql(u8, self.paths[index][0..self.path_lens[index]], path)) continue;
            self.removeAt(index);
            return;
        }
        self.add(path);
    }

    pub fn collapseAll(self: *CollapseStore, nodes: []const workspace_store.FileNode) void {
        self.clear();
        for (nodes) |node| {
            if (node.is_dir) self.add(node.path);
        }
    }

    pub fn expandAncestors(self: *CollapseStore, path: []const u8) void {
        var index: usize = 0;
        while (index < self.count) {
            const collapsed = self.paths[index][0..self.path_lens[index]];
            if (isDescendant(path, collapsed)) {
                self.removeAt(index);
            } else {
                index += 1;
            }
        }
    }

    pub fn prune(self: *CollapseStore, nodes: []const workspace_store.FileNode) void {
        var index: usize = 0;
        while (index < self.count) {
            const path = self.paths[index][0..self.path_lens[index]];
            var found = false;
            for (nodes) |node| {
                if (node.is_dir and std.mem.eql(u8, node.path, path)) {
                    found = true;
                    break;
                }
            }
            if (found) {
                index += 1;
            } else {
                self.removeAt(index);
            }
        }
    }

    fn add(self: *CollapseStore, path: []const u8) void {
        if (path.len == 0 or path.len > scanner.max_rel_path_len or self.count >= max_collapsed or self.contains(path)) return;
        const index = self.count;
        @memcpy(self.paths[index][0..path.len], path);
        self.path_lens[index] = @intCast(path.len);
        self.count += 1;
    }

    fn removeAt(self: *CollapseStore, index: usize) void {
        var cursor = index;
        while (cursor + 1 < self.count) : (cursor += 1) {
            self.path_lens[cursor] = self.path_lens[cursor + 1];
            @memcpy(
                self.paths[cursor][0..self.path_lens[cursor]],
                self.paths[cursor + 1][0..self.path_lens[cursor]],
            );
        }
        self.count -= 1;
    }
};

pub const Projection = struct {
    nodes: [scanner.max_nodes]workspace_store.FileNode = [_]workspace_store.FileNode{.{}} ** scanner.max_nodes,
    count: u16 = 0,
    chevron_labels: [scanner.max_nodes][scanner.max_name_len + 18]u8 = undefined,
    chevron_label_lens: [scanner.max_nodes]u8 = [_]u8{0} ** scanner.max_nodes,

    pub fn slice(self: *Projection) []const workspace_store.FileNode {
        return self.nodes[0..self.count];
    }

    pub fn rebuild(
        self: *Projection,
        full_tree: []const workspace_store.FileNode,
        collapsed: *const CollapseStore,
        query: []const u8,
        statuses: []const git_status.GitEntry,
    ) void {
        self.count = 0;
        if (query.len > 0) {
            for (full_tree) |node| {
                if (self.matchesFilter(full_tree, node, query)) self.append(node, collapsed, statuses);
            }
            return;
        }

        var hidden_below_depth: ?u8 = null;
        for (full_tree) |node| {
            if (hidden_below_depth) |depth| {
                if (node.depth > depth) continue;
                hidden_below_depth = null;
            }
            self.append(node, collapsed, statuses);
            if (node.is_dir and collapsed.contains(node.path)) hidden_below_depth = node.depth;
        }
    }

    fn matchesFilter(
        self: *const Projection,
        full_tree: []const workspace_store.FileNode,
        node: workspace_store.FileNode,
        query: []const u8,
    ) bool {
        _ = self;
        if (matches(node, query)) return true;
        if (!node.is_dir) return false;
        for (full_tree) |candidate| {
            if (isDescendant(candidate.path, node.path) and matches(candidate, query)) return true;
        }
        return false;
    }

    fn append(
        self: *Projection,
        source: workspace_store.FileNode,
        collapsed: *const CollapseStore,
        statuses: []const git_status.GitEntry,
    ) void {
        if (self.count >= self.nodes.len) return;
        const index = self.count;
        var node = workspace_store.decorateFileNode(source);
        node.chevron = if (!node.is_dir) "" else if (collapsed.contains(node.path)) "›" else "⌄";
        if (node.is_dir) {
            const action = if (collapsed.contains(node.path)) "Expand" else "Collapse";
            const label = std.fmt.bufPrint(&self.chevron_labels[index], "{s} {s}", .{ action, node.name }) catch action;
            self.chevron_label_lens[index] = @intCast(label.len);
            node.chevron_label = self.chevron_labels[index][0..label.len];
        }
        node.scm_label = statusLabel(statuses, node.path);
        node.has_scm = node.scm_label.len > 0;
        self.nodes[index] = node;
        self.count += 1;
    }
};

fn matches(node: workspace_store.FileNode, query: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(node.name, query) != null or
        std.ascii.indexOfIgnoreCase(node.path, query) != null;
}

fn isDescendant(path: []const u8, ancestor: []const u8) bool {
    return path.len > ancestor.len and
        std.mem.startsWith(u8, path, ancestor) and
        path[ancestor.len] == '/';
}

fn statusLabel(statuses: []const git_status.GitEntry, path: []const u8) []const u8 {
    for (statuses) |entry| {
        if (!std.mem.eql(u8, entry.path, path)) continue;
        const x = if (entry.status.len > 0) entry.status[0] else ' ';
        const y = if (entry.status.len > 1) entry.status[1] else ' ';
        if (x == 'U' or y == 'U' or
            (x == 'A' and y == 'A') or
            (x == 'D' and y == 'D')) return "Conflict";
        if (x == '?' or y == '?') return "Untracked";
        if (x != ' ' and y != ' ') return "Staged + Modified";
        if (x != ' ') return "Staged";
        if (y != ' ') return "Modified";
        return "";
    }
    return "";
}

test "projection collapses descendants and filter includes matching ancestors" {
    const nodes = [_]workspace_store.FileNode{
        .{ .id = 1, .name = "src", .path = "src", .depth = 0, .is_dir = true },
        .{ .id = 2, .name = "nested", .path = "src/nested", .depth = 1, .is_dir = true },
        .{ .id = 3, .name = "match.ts", .path = "src/nested/match.ts", .depth = 2 },
        .{ .id = 4, .name = "README.md", .path = "README.md", .depth = 0 },
    };
    var collapsed: CollapseStore = .{};
    collapsed.toggle("src");
    var projection: Projection = .{};
    projection.rebuild(&nodes, &collapsed, "", &.{});
    try std.testing.expectEqual(@as(usize, 2), projection.slice().len);
    try std.testing.expectEqualStrings("src", projection.slice()[0].path);

    projection.rebuild(&nodes, &collapsed, "match", &.{});
    try std.testing.expectEqual(@as(usize, 3), projection.slice().len);
    try std.testing.expectEqualStrings("src", projection.slice()[0].path);
    try std.testing.expectEqualStrings("src/nested", projection.slice()[1].path);
    try std.testing.expectEqualStrings("src/nested/match.ts", projection.slice()[2].path);

    projection.rebuild(&nodes, &collapsed, "", &.{});
    try std.testing.expectEqual(@as(usize, 2), projection.slice().len);
}

test "collapse store expands ancestors and prunes stale paths" {
    const nodes = [_]workspace_store.FileNode{
        .{ .name = "src", .path = "src", .is_dir = true },
        .{ .name = "nested", .path = "src/nested", .is_dir = true },
    };
    var collapsed: CollapseStore = .{};
    collapsed.collapseAll(&nodes);
    collapsed.expandAncestors("src/nested/file.ts");
    try std.testing.expectEqual(@as(u16, 0), collapsed.count);
    collapsed.toggle("src/nested");
    collapsed.prune(nodes[0..1]);
    try std.testing.expectEqual(@as(u16, 0), collapsed.count);
}

test "projection maps porcelain states without per-row work" {
    const nodes = [_]workspace_store.FileNode{
        .{ .id = 1, .name = "modified", .path = "modified" },
        .{ .id = 2, .name = "staged", .path = "staged" },
        .{ .id = 3, .name = "new", .path = "new" },
        .{ .id = 4, .name = "conflict", .path = "conflict" },
    };
    const statuses = [_]git_status.GitEntry{
        .{ .status = " M", .path = "modified" },
        .{ .status = "A ", .path = "staged" },
        .{ .status = "??", .path = "new" },
        .{ .status = "UU", .path = "conflict" },
    };
    var projection: Projection = .{};
    var collapsed: CollapseStore = .{};
    projection.rebuild(&nodes, &collapsed, "", &statuses);
    try std.testing.expectEqualStrings("Modified", projection.nodes[0].scm_label);
    try std.testing.expectEqualStrings("Staged", projection.nodes[1].scm_label);
    try std.testing.expectEqualStrings("Untracked", projection.nodes[2].scm_label);
    try std.testing.expectEqualStrings("Conflict", projection.nodes[3].scm_label);
}
