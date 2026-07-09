//! Bounded undo/redo histories keyed by workspace-relative tab path.
//! A history is owned only while its tab is open.

const std = @import("std");
const scanner = @import("scanner.zig");
const undo_stack = @import("undo_stack.zig");

pub const max_histories: usize = 8;

const Slot = struct {
    path: [scanner.max_rel_path_len]u8 = undefined,
    path_len: usize = 0,
    history: undo_stack.UndoStack,

    fn pathSlice(self: *const Slot) []const u8 {
        return self.path[0..self.path_len];
    }
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    slots: [max_histories]?Slot = [_]?Slot{null} ** max_histories,

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Store) void {
        self.clear();
        self.* = undefined;
    }

    pub fn clear(self: *Store) void {
        for (&self.slots) |*slot| {
            if (slot.*) |*value| value.history.deinit();
            slot.* = null;
        }
    }

    pub fn get(self: *Store, path: []const u8) ?*undo_stack.UndoStack {
        for (&self.slots) |*slot| {
            if (slot.*) |*value| {
                if (std.mem.eql(u8, value.pathSlice(), path)) return &value.history;
            }
        }
        return null;
    }

    pub fn ensure(
        self: *Store,
        path: []const u8,
        initial_text: []const u8,
        options: undo_stack.Options,
    ) !*undo_stack.UndoStack {
        if (path.len == 0 or path.len > scanner.max_rel_path_len) return error.InvalidPath;
        if (self.get(path)) |history| return history;
        for (&self.slots) |*slot| {
            if (slot.* != null) continue;
            var value: Slot = .{
                .history = try undo_stack.UndoStack.init(self.allocator, options),
            };
            errdefer value.history.deinit();
            @memcpy(value.path[0..path.len], path);
            value.path_len = path.len;
            _ = try value.history.record(initial_text);
            slot.* = value;
            return &slot.*.?.history;
        }
        return error.TooManyHistories;
    }

    pub fn remove(self: *Store, path: []const u8) void {
        for (&self.slots) |*slot| {
            if (slot.*) |*value| {
                if (!std.mem.eql(u8, value.pathSlice(), path)) continue;
                value.history.deinit();
                slot.* = null;
                return;
            }
        }
    }

    pub fn retainPaths(self: *Store, paths: []const []const u8) void {
        for (&self.slots) |*slot| {
            if (slot.*) |*value| {
                var keep = false;
                for (paths) |path| {
                    if (std.mem.eql(u8, value.pathSlice(), path)) {
                        keep = true;
                        break;
                    }
                }
                if (!keep) {
                    value.history.deinit();
                    slot.* = null;
                }
            }
        }
    }

    pub fn rename(self: *Store, old_path: []const u8, new_path: []const u8) !void {
        if (new_path.len == 0 or new_path.len > scanner.max_rel_path_len) return error.InvalidPath;
        for (&self.slots) |*slot| {
            if (slot.*) |*value| {
                if (!std.mem.eql(u8, value.pathSlice(), old_path)) continue;
                @memcpy(value.path[0..new_path.len], new_path);
                value.path_len = new_path.len;
                return;
            }
        }
    }

    pub fn count(self: *const Store) usize {
        var total: usize = 0;
        for (self.slots) |slot| {
            if (slot != null) total += 1;
        }
        return total;
    }
};

test "histories remain isolated by path and release removed tabs" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const options: undo_stack.Options = .{ .max_entries = 4, .max_bytes = 64 };
    const a = try store.ensure("a.txt", "a0", options);
    _ = try a.record("a1");
    const b = try store.ensure("b.txt", "b0", options);
    _ = try b.record("b1");

    var output: [16]u8 = undefined;
    try std.testing.expectEqualStrings("a0", (try a.undo(&output)).?);
    try std.testing.expectEqualStrings("b1", b.current().?);

    const paths = [_][]const u8{"b.txt"};
    store.retainPaths(&paths);
    try std.testing.expect(store.get("a.txt") == null);
    try std.testing.expect(store.get("b.txt") != null);
    try std.testing.expectEqual(@as(usize, 1), store.count());
}
