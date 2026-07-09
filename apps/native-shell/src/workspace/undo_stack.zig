//! Bounded text snapshot history for one editor tab.
//! The caller chooses both the entry and byte budgets and must call `deinit`.

const std = @import("std");

pub const Options = struct {
    max_entries: usize = 64,
    max_bytes: usize = 256 * 1024,
};

const Entry = struct {
    text: []u8,
};

pub const UndoStack = struct {
    allocator: std.mem.Allocator,
    entries: []Entry,
    count: usize = 0,
    cursor: usize = 0,
    bytes_used: usize = 0,
    max_bytes: usize,

    pub fn init(allocator: std.mem.Allocator, options: Options) !UndoStack {
        if (options.max_entries == 0 or options.max_bytes == 0) {
            return error.InvalidOptions;
        }
        return .{
            .allocator = allocator,
            .entries = try allocator.alloc(Entry, options.max_entries),
            .max_bytes = options.max_bytes,
        };
    }

    pub fn deinit(self: *UndoStack) void {
        self.clear();
        self.allocator.free(self.entries);
        self.* = undefined;
    }

    pub fn clear(self: *UndoStack) void {
        self.truncate(0);
        self.cursor = 0;
    }

    /// Records the complete document state after an edit.
    /// Returns false when the state is identical to the current snapshot.
    pub fn record(self: *UndoStack, text: []const u8) !bool {
        if (text.len > self.max_bytes) return error.SnapshotTooLarge;
        if (self.current()) |current_text| {
            if (std.mem.eql(u8, current_text, text)) return false;
        }

        // Allocate before changing history so allocation failure is atomic.
        const owned = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned);

        if (self.count > 0) self.truncate(self.cursor + 1);
        while (self.count == self.entries.len or owned.len > self.max_bytes - self.bytes_used) {
            self.removeOldest();
        }

        self.entries[self.count] = .{ .text = owned };
        self.count += 1;
        self.bytes_used += owned.len;
        self.cursor = self.count - 1;
        return true;
    }

    pub fn canUndo(self: *const UndoStack) bool {
        return self.count > 0 and self.cursor > 0;
    }

    pub fn canRedo(self: *const UndoStack) bool {
        return self.count > 0 and self.cursor + 1 < self.count;
    }

    /// Copies the previous state into `output`; returns null at oldest state.
    pub fn undo(self: *UndoStack, output: []u8) !?[]u8 {
        if (!self.canUndo()) return null;
        const next_cursor = self.cursor - 1;
        const text = self.entries[next_cursor].text;
        if (output.len < text.len) return error.OutputTooSmall;
        @memcpy(output[0..text.len], text);
        self.cursor = next_cursor;
        return output[0..text.len];
    }

    /// Copies the next state into `output`; returns null at newest state.
    pub fn redo(self: *UndoStack, output: []u8) !?[]u8 {
        if (!self.canRedo()) return null;
        const next_cursor = self.cursor + 1;
        const text = self.entries[next_cursor].text;
        if (output.len < text.len) return error.OutputTooSmall;
        @memcpy(output[0..text.len], text);
        self.cursor = next_cursor;
        return output[0..text.len];
    }

    pub fn current(self: *const UndoStack) ?[]const u8 {
        if (self.count == 0) return null;
        return self.entries[self.cursor].text;
    }

    pub fn entryCount(self: *const UndoStack) usize {
        return self.count;
    }

    pub fn byteCount(self: *const UndoStack) usize {
        return self.bytes_used;
    }

    fn truncate(self: *UndoStack, new_count: usize) void {
        var i = new_count;
        while (i < self.count) : (i += 1) {
            self.bytes_used -= self.entries[i].text.len;
            self.allocator.free(self.entries[i].text);
        }
        self.count = new_count;
        if (self.count == 0) {
            self.cursor = 0;
        } else if (self.cursor >= self.count) {
            self.cursor = self.count - 1;
        }
    }

    fn removeOldest(self: *UndoStack) void {
        std.debug.assert(self.count > 0);
        self.bytes_used -= self.entries[0].text.len;
        self.allocator.free(self.entries[0].text);
        std.mem.copyForwards(Entry, self.entries[0 .. self.count - 1], self.entries[1..self.count]);
        self.count -= 1;
        if (self.cursor > 0) self.cursor -= 1;
    }
};

test "undo and redo traverse document snapshots" {
    var stack = try UndoStack.init(std.testing.allocator, .{});
    defer stack.deinit();

    try std.testing.expect(try stack.record("one"));
    try std.testing.expect(try stack.record("one two"));
    try std.testing.expect(try stack.record("one two three"));
    try std.testing.expect(!(try stack.record("one two three")));

    var output: [64]u8 = undefined;
    try std.testing.expectEqualStrings("one two", (try stack.undo(&output)).?);
    try std.testing.expectEqualStrings("one", (try stack.undo(&output)).?);
    try std.testing.expect((try stack.undo(&output)) == null);
    try std.testing.expectEqualStrings("one two", (try stack.redo(&output)).?);
    try std.testing.expectEqualStrings("one two three", (try stack.redo(&output)).?);
    try std.testing.expect((try stack.redo(&output)) == null);
}

test "record after undo discards redo history" {
    var stack = try UndoStack.init(std.testing.allocator, .{ .max_entries = 4, .max_bytes = 64 });
    defer stack.deinit();

    _ = try stack.record("a");
    _ = try stack.record("ab");
    _ = try stack.record("abc");

    var output: [16]u8 = undefined;
    _ = try stack.undo(&output);
    _ = try stack.record("ab!");

    try std.testing.expect(!stack.canRedo());
    try std.testing.expectEqualStrings("ab", (try stack.undo(&output)).?);
    try std.testing.expectEqualStrings("ab!", (try stack.redo(&output)).?);
}

test "budgets evict oldest snapshots and reject oversized states" {
    var stack = try UndoStack.init(std.testing.allocator, .{ .max_entries = 3, .max_bytes = 8 });
    defer stack.deinit();

    _ = try stack.record("1111");
    _ = try stack.record("2222");
    _ = try stack.record("3333");
    try std.testing.expectEqual(@as(usize, 2), stack.entryCount());
    try std.testing.expectEqual(@as(usize, 8), stack.byteCount());

    var output: [8]u8 = undefined;
    try std.testing.expectEqualStrings("2222", (try stack.undo(&output)).?);
    try std.testing.expect((try stack.undo(&output)) == null);
    try std.testing.expectError(error.SnapshotTooLarge, stack.record("123456789"));
}

test "small output leaves history position unchanged" {
    var stack = try UndoStack.init(std.testing.allocator, .{});
    defer stack.deinit();

    _ = try stack.record("short");
    _ = try stack.record("a longer state");

    var small: [2]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, stack.undo(&small));
    try std.testing.expect(stack.canUndo());
}
