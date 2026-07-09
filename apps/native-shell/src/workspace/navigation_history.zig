//! Bounded editor navigation history.

const std = @import("std");
const scanner = @import("scanner.zig");

pub const max_entries: usize = 32;

pub const Location = struct {
    path: []const u8 = "",
    line: u32 = 1,
};

pub const History = struct {
    entries: [max_entries]Location = [_]Location{.{}} ** max_entries,
    path_pool: [max_entries][scanner.max_rel_path_len]u8 = undefined,
    path_lens: [max_entries]usize = [_]usize{0} ** max_entries,
    count: u32 = 0,
    cursor: u32 = 0,

    pub fn clear(self: *History) void {
        self.count = 0;
        self.cursor = 0;
    }

    pub fn canBack(self: *const History) bool {
        return self.count > 1 and self.cursor > 0;
    }

    pub fn canForward(self: *const History) bool {
        return self.count > 0 and self.cursor + 1 < self.count;
    }

    /// Record the source and destination as one user navigation. Recording a
    /// new destination after Back truncates the abandoned forward branch.
    pub fn recordTransition(self: *History, from: Location, to: Location) void {
        if (from.path.len == 0 or to.path.len == 0 or same(from, to)) return;
        if (self.count == 0) {
            self.append(from);
        } else if (!same(self.entries[self.cursor], from)) {
            self.truncateForward();
            self.append(from);
        }
        if (self.count > 0 and same(self.entries[self.cursor], to)) return;
        self.truncateForward();
        self.append(to);
    }

    pub fn back(self: *History) ?Location {
        if (!self.canBack()) return null;
        self.cursor -= 1;
        return self.entries[self.cursor];
    }

    pub fn forward(self: *History) ?Location {
        if (!self.canForward()) return null;
        self.cursor += 1;
        return self.entries[self.cursor];
    }

    fn truncateForward(self: *History) void {
        if (self.count > 0 and self.cursor + 1 < self.count) {
            self.count = self.cursor + 1;
        }
    }

    fn append(self: *History, location: Location) void {
        if (location.path.len == 0) return;
        if (self.count > 0 and same(self.entries[self.count - 1], location)) {
            self.cursor = self.count - 1;
            return;
        }
        if (self.count == max_entries) {
            var i: usize = 1;
            while (i < max_entries) : (i += 1) self.copyEntry(i - 1, i);
            self.count -= 1;
            if (self.cursor > 0) self.cursor -= 1;
        }
        const index: usize = self.count;
        const path_len = @min(location.path.len, scanner.max_rel_path_len);
        @memcpy(self.path_pool[index][0..path_len], location.path[0..path_len]);
        self.path_lens[index] = path_len;
        self.entries[index] = .{
            .path = self.path_pool[index][0..path_len],
            .line = @max(location.line, 1),
        };
        self.count += 1;
        self.cursor = self.count - 1;
    }

    fn copyEntry(self: *History, destination: usize, source: usize) void {
        const path_len = self.path_lens[source];
        @memcpy(self.path_pool[destination][0..path_len], self.path_pool[source][0..path_len]);
        self.path_lens[destination] = path_len;
        self.entries[destination] = .{
            .path = self.path_pool[destination][0..path_len],
            .line = self.entries[source].line,
        };
    }
};

fn same(left: Location, right: Location) bool {
    return left.line == right.line and std.mem.eql(u8, left.path, right.path);
}

test "history deduplicates, branches, and stays bounded" {
    var history: History = .{};
    history.recordTransition(.{ .path = "a.zig", .line = 1 }, .{ .path = "b.zig", .line = 2 });
    history.recordTransition(.{ .path = "b.zig", .line = 2 }, .{ .path = "b.zig", .line = 2 });
    try std.testing.expectEqual(@as(u32, 2), history.count);
    try std.testing.expectEqualStrings("a.zig", history.back().?.path);
    history.recordTransition(.{ .path = "a.zig", .line = 1 }, .{ .path = "c.zig", .line = 3 });
    try std.testing.expect(!history.canForward());
    try std.testing.expectEqualStrings("c.zig", history.entries[history.cursor].path);

    var i: u32 = 0;
    while (i < max_entries + 4) : (i += 1) {
        var path_buf: [24]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "file-{d}.zig", .{i});
        history.recordTransition(history.entries[history.cursor], .{ .path = path, .line = i + 1 });
    }
    try std.testing.expectEqual(@as(u32, max_entries), history.count);
}
