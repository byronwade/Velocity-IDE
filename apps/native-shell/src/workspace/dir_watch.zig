//! Bounded directory-change watcher (tiered polling; no OS file events in
//! the SDK). After each workspace scan the watcher baselines the mtime of
//! every scanned directory plus the root; each poll tick re-stats a small
//! round-robin budget of them. A directory's mtime changes when direct
//! children are created, deleted, or renamed, so any change inside the
//! scanned tree is detected within (dir_count / budget) ticks - bounded
//! latency, zero processes, zero allocations.

const std = @import("std");
const scanner = @import("scanner.zig");
const workspace_store = @import("workspace_store.zig");

/// Every scanned node could be a directory, plus one slot for the root.
pub const max_dirs: usize = scanner.max_nodes + 1;

const Slot = struct {
    /// Hash of the rel path so a reshaped tree never aliases a stale mtime.
    path_hash: u64 = 0,
    mtime_ns: i128 = 0,
};

pub const Watcher = struct {
    slots: [max_dirs]Slot = [_]Slot{.{}} ** max_dirs,
    dir_count: usize = 0,
    next_index: usize = 0,
    baselined: bool = false,

    /// Capture the current mtimes of the root and every scanned directory.
    /// Call after every scan/rescan so detection state matches the tree.
    pub fn baseline(
        self: *Watcher,
        io: std.Io,
        root_path: []const u8,
        nodes: []const workspace_store.FileNode,
    ) void {
        self.dir_count = 0;
        self.next_index = 0;
        self.baselined = false;
        if (root_path.len == 0) return;

        self.slots[0] = .{ .path_hash = pathHash(""), .mtime_ns = dirMtime(io, root_path, "") orelse 0 };
        self.dir_count = 1;
        for (nodes) |node| {
            if (!node.is_dir) continue;
            if (self.dir_count >= self.slots.len) break;
            self.slots[self.dir_count] = .{
                .path_hash = pathHash(node.path),
                .mtime_ns = dirMtime(io, root_path, node.path) orelse 0,
            };
            self.dir_count += 1;
        }
        self.baselined = true;
    }

    /// Re-stat up to `budget` watched directories. Returns true when any of
    /// them changed (mtime moved, vanished, or the tree reshaped under the
    /// slot). The caller rescans and then re-baselines.
    pub fn check(
        self: *Watcher,
        io: std.Io,
        root_path: []const u8,
        nodes: []const workspace_store.FileNode,
        budget: usize,
    ) bool {
        if (!self.baselined or self.dir_count == 0 or budget == 0) return false;
        var checked: usize = 0;
        while (checked < budget and checked < self.dir_count) : (checked += 1) {
            const index = self.next_index % self.dir_count;
            self.next_index = (self.next_index + 1) % self.dir_count;
            const slot = self.slots[index];
            if (index == 0) {
                const now = dirMtime(io, root_path, "") orelse return true;
                if (now != slot.mtime_ns) return true;
                continue;
            }
            // Re-resolve the node for this slot; a reshaped tree is a change.
            const rel = dirRelForSlot(nodes, index) orelse return true;
            if (pathHash(rel) != slot.path_hash) return true;
            const now = dirMtime(io, root_path, rel) orelse return true;
            if (now != slot.mtime_ns) return true;
        }
        return false;
    }

    pub fn reset(self: *Watcher) void {
        self.dir_count = 0;
        self.next_index = 0;
        self.baselined = false;
    }
};

/// The Nth directory (1-based slot index; slot 0 is the root) in node order.
fn dirRelForSlot(nodes: []const workspace_store.FileNode, slot_index: usize) ?[]const u8 {
    var seen: usize = 0;
    for (nodes) |node| {
        if (!node.is_dir) continue;
        seen += 1;
        if (seen == slot_index) return node.path;
    }
    return null;
}

fn pathHash(path: []const u8) u64 {
    return std.hash.Wyhash.hash(0x76656c6f, path);
}

fn dirMtime(io: std.Io, root_path: []const u8, rel: []const u8) ?i128 {
    var root = std.Io.Dir.cwd().openDir(io, root_path, .{}) catch return null;
    defer root.close(io);
    if (rel.len == 0) {
        const stat = root.stat(io) catch return null;
        return stat.mtime.nanoseconds;
    }
    var dir = root.openDir(io, rel, .{}) catch return null;
    defer dir.close(io);
    const stat = dir.stat(io) catch return null;
    return stat.mtime.nanoseconds;
}

test "watcher detects created deleted and renamed entries at any scanned depth" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "src/deep");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "src/deep/a.txt", .data = "a\n" });
    var path_buf: [512]u8 = undefined;
    const root_len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const root = path_buf[0..root_len];

    const ws = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(ws);
    ws.* = .{};
    _ = try ws.openPath(std.testing.io, root);

    var watcher: Watcher = .{};
    watcher.baseline(std.testing.io, root, ws.fileNodesSlice());
    try std.testing.expect(watcher.dir_count >= 3); // root, src, src/deep

    // Quiet tree: a full sweep reports no change.
    try std.testing.expect(!watcher.check(std.testing.io, root, ws.fileNodesSlice(), max_dirs));

    // A file created in a nested dir flips that dir's mtime.
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "src/deep/b.txt", .data = "b\n" });
    try std.testing.expect(watcher.check(std.testing.io, root, ws.fileNodesSlice(), max_dirs));

    // Rescan + re-baseline settles it again.
    _ = try ws.rescanPreserveTabs(std.testing.io, "");
    watcher.baseline(std.testing.io, root, ws.fileNodesSlice());
    try std.testing.expect(!watcher.check(std.testing.io, root, ws.fileNodesSlice(), max_dirs));

    // Deleting a watched directory is a change (stat fails).
    try tmp.dir.deleteTree(std.testing.io, "src/deep");
    try std.testing.expect(watcher.check(std.testing.io, root, ws.fileNodesSlice(), max_dirs));
}

test "unbaselined or empty watcher never reports changes" {
    var watcher: Watcher = .{};
    try std.testing.expect(!watcher.check(std.testing.io, "/nonexistent", &.{}, 8));
    watcher.reset();
    try std.testing.expect(!watcher.check(std.testing.io, "", &.{}, 8));
}
