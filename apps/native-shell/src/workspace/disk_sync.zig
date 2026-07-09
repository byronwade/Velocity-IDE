//! Bounded, round-robin polling for external changes to open files.
//! Polling is synchronous and checks at most the caller-provided budget.

const std = @import("std");
const file_fingerprint = @import("file_fingerprint.zig");
const workspace_store = @import("workspace_store.zig");

pub const Event = struct {
    tab_id: u32,
    tab_index: usize,
    path: []const u8,
};

pub const Batch = struct {
    events: [workspace_store.max_open_tabs]Event = undefined,
    event_count: usize = 0,
    checked_count: usize = 0,

    pub fn eventSlice(self: *const Batch) []const Event {
        return self.events[0..self.event_count];
    }
};

pub const Checker = struct {
    next_index: usize = 0,
    known_ids: [workspace_store.max_open_tabs]u32 = [_]u32{0} ** workspace_store.max_open_tabs,
    known_paths: [workspace_store.max_open_tabs]file_fingerprint.Fingerprint = [_]file_fingerprint.Fingerprint{.{}} ** workspace_store.max_open_tabs,
    stale: [workspace_store.max_open_tabs]bool = [_]bool{false} ** workspace_store.max_open_tabs,

    /// Checks up to `budget` open tabs and reports only fresh transitions to stale.
    /// Event paths borrow from `workspace` and remain valid until its tabs change.
    pub fn check(
        self: *Checker,
        io: std.Io,
        workspace: *workspace_store.WorkspaceBuffers,
        budget: usize,
    ) Batch {
        self.reconcileTabs(workspace);
        var batch = Batch{};
        const tab_count = workspace.tabsSlice().len;
        if (tab_count == 0 or budget == 0) return batch;

        const check_count = @min(budget, tab_count);
        var checked: usize = 0;
        while (checked < check_count) : (checked += 1) {
            const index = self.next_index;
            const tab = workspace.tabsSlice()[index];
            const changed = file_fingerprint.changed(
                io,
                workspace.rootPath(),
                tab.path,
                workspace.tab_disk_fingerprints[index],
            );
            if (changed and !self.stale[index]) {
                batch.events[batch.event_count] = .{
                    .tab_id = tab.id,
                    .tab_index = index,
                    .path = tab.path,
                };
                batch.event_count += 1;
            }
            self.stale[index] = changed;
            self.next_index = (index + 1) % tab_count;
        }
        batch.checked_count = check_count;
        return batch;
    }

    pub fn isStale(self: *const Checker, tab_id: u32) bool {
        for (self.known_ids, self.stale) |known_id, stale| {
            if (known_id == tab_id) return stale;
        }
        return false;
    }

    pub fn clearStale(self: *Checker, tab_id: u32) void {
        for (&self.known_ids, &self.stale) |*known_id, *stale| {
            if (known_id.* == tab_id) {
                stale.* = false;
                return;
            }
        }
    }

    pub fn reset(self: *Checker) void {
        self.* = .{};
    }

    fn reconcileTabs(
        self: *Checker,
        workspace: *workspace_store.WorkspaceBuffers,
    ) void {
        const old_ids = self.known_ids;
        const old_paths = self.known_paths;
        const old_stale = self.stale;
        self.known_ids = [_]u32{0} ** workspace_store.max_open_tabs;
        self.known_paths = [_]file_fingerprint.Fingerprint{.{}} ** workspace_store.max_open_tabs;
        self.stale = [_]bool{false} ** workspace_store.max_open_tabs;

        for (workspace.tabsSlice(), 0..) |tab, new_index| {
            const path_fingerprint = file_fingerprint.ofBytes(tab.path);
            self.known_ids[new_index] = tab.id;
            self.known_paths[new_index] = path_fingerprint;
            for (old_ids, old_paths, old_stale) |old_id, old_path, was_stale| {
                if (old_id == tab.id and sameFingerprint(old_path, path_fingerprint)) {
                    self.stale[new_index] = was_stale;
                    break;
                }
            }
        }

        const tab_count = workspace.tabsSlice().len;
        if (tab_count == 0) {
            self.next_index = 0;
        } else {
            self.next_index %= tab_count;
        }
    }
};

fn sameFingerprint(a: file_fingerprint.Fingerprint, b: file_fingerprint.Fingerprint) bool {
    return a.valid == b.valid and a.len == b.len and a.hash == b.hash;
}

test "checker bounds work and reports each external change once" {
    const root = "zig-out/test-disk-sync";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/b.txt", .data = "b" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/c.txt", .data = "c" });

    const workspace = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(workspace);
    workspace.* = .{};
    _ = try workspace.openPath(std.testing.io, root);
    const b = workspace.findNodeByPath("b.txt").?;
    const c = workspace.findNodeByPath("c.txt").?;
    try workspace.openFileById(std.testing.io, b.id);
    try workspace.openFileById(std.testing.io, c.id);

    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/b.txt", .data = "external" });

    var checker = Checker{};
    const first = checker.check(std.testing.io, workspace, 1);
    try std.testing.expectEqual(@as(usize, 1), first.checked_count);
    try std.testing.expectEqual(@as(usize, 0), first.event_count);

    const second = checker.check(std.testing.io, workspace, 1);
    try std.testing.expectEqual(@as(usize, 1), second.event_count);
    try std.testing.expectEqual(b.id, second.eventSlice()[0].tab_id);
    try std.testing.expectEqual(@as(usize, 1), second.eventSlice()[0].tab_index);
    try std.testing.expectEqualStrings("b.txt", second.eventSlice()[0].path);
    try std.testing.expect(checker.isStale(b.id));

    _ = checker.check(std.testing.io, workspace, 1);
    _ = checker.check(std.testing.io, workspace, 1);
    const repeated = checker.check(std.testing.io, workspace, 1);
    try std.testing.expectEqual(@as(usize, 0), repeated.event_count);
}

test "checker clears stale state after baseline content returns" {
    const root = "zig-out/test-disk-sync-clear";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "original" });

    const workspace = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(workspace);
    workspace.* = .{};
    _ = try workspace.openPath(std.testing.io, root);
    const tab_id = workspace.tabsSlice()[0].id;

    var checker = Checker{};
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "changed" });
    try std.testing.expectEqual(@as(usize, 1), checker.check(std.testing.io, workspace, 8).event_count);
    try std.testing.expect(checker.isStale(tab_id));

    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "original" });
    try std.testing.expectEqual(@as(usize, 0), checker.check(std.testing.io, workspace, 8).event_count);
    try std.testing.expect(!checker.isStale(tab_id));

    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "changed again" });
    try std.testing.expectEqual(@as(usize, 1), checker.check(std.testing.io, workspace, 8).event_count);
}
