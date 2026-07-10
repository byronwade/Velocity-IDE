//! Bounded operation-based text history for one editor tab.
//! Stores one materialized copy of the state at the history cursor plus
//! reverse patches (offset/removed/inserted spans) between adjacent states,
//! so a keystroke costs bytes proportional to the edit — not the document.
//! Contiguous typing and backspace runs coalesce into grouped operations.
//! The caller chooses both the entry and byte budgets and must call `deinit`.

const std = @import("std");

pub const Options = struct {
    max_entries: usize = 64,
    max_bytes: usize = 256 * 1024,
};

/// Typing runs coalesce into one grouped operation up to this many bytes;
/// newlines always start a new group so undo stops at line boundaries.
pub const typing_group_limit: usize = 64;

/// One transition between adjacent states: `new = old` with
/// `old[offset..offset+removed.len]` replaced by `inserted`.
const Patch = struct {
    offset: usize,
    removed: []u8,
    inserted: []u8,

    fn cost(self: Patch) usize {
        return self.removed.len + self.inserted.len;
    }
};

pub const UndoStack = struct {
    allocator: std.mem.Allocator,
    patches: []Patch,
    /// Number of recorded transitions (states reachable = patch_count + 1).
    patch_count: usize = 0,
    /// Number of transitions below the cursor (cursor state index).
    cursor: usize = 0,
    /// Materialized text of the state at the cursor; null until first record.
    current_text: ?[]u8 = null,
    bytes_used: usize = 0,
    max_bytes: usize,

    pub fn init(allocator: std.mem.Allocator, options: Options) !UndoStack {
        if (options.max_entries == 0 or options.max_bytes == 0) {
            return error.InvalidOptions;
        }
        return .{
            .allocator = allocator,
            .patches = try allocator.alloc(Patch, options.max_entries),
            .max_bytes = options.max_bytes,
        };
    }

    pub fn deinit(self: *UndoStack) void {
        self.clear();
        self.allocator.free(self.patches);
        self.* = undefined;
    }

    pub fn clear(self: *UndoStack) void {
        var i: usize = 0;
        while (i < self.patch_count) : (i += 1) self.freePatch(self.patches[i]);
        self.patch_count = 0;
        self.cursor = 0;
        if (self.current_text) |text| self.allocator.free(text);
        self.current_text = null;
        self.bytes_used = 0;
    }

    /// Records the complete document state after an edit.
    /// Returns false when the state is identical to the current snapshot.
    pub fn record(self: *UndoStack, text: []const u8) !bool {
        if (text.len > self.max_bytes) return error.SnapshotTooLarge;
        const old = self.current_text orelse {
            const owned = try self.allocator.dupe(u8, text);
            self.current_text = owned;
            self.bytes_used = owned.len;
            return true;
        };
        if (std.mem.eql(u8, old, text)) return false;

        const span = diffSpan(old, text);
        // Allocate everything before mutating history so failure is atomic.
        const removed = try self.allocator.dupe(u8, old[span.offset..][0..span.removed_len]);
        errdefer self.allocator.free(removed);
        const inserted = try self.allocator.dupe(u8, text[span.offset..][0..span.inserted_len]);
        errdefer self.allocator.free(inserted);
        const owned = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned);

        // A record while undone discards the redo tail.
        while (self.patch_count > self.cursor) {
            self.patch_count -= 1;
            self.bytes_used -= self.patches[self.patch_count].cost();
            self.freePatch(self.patches[self.patch_count]);
        }

        self.bytes_used -= old.len;
        self.allocator.free(old);
        self.current_text = owned;
        self.bytes_used += owned.len;

        if (self.tryCoalesce(span.offset, removed, inserted)) {
            self.enforceBudget();
            return true;
        }

        while (self.patch_count == self.patches.len or
            (self.patch_count > 0 and self.bytes_used + removed.len + inserted.len > self.max_bytes))
        {
            self.removeOldest();
        }
        self.patches[self.patch_count] = .{ .offset = span.offset, .removed = removed, .inserted = inserted };
        self.patch_count += 1;
        self.bytes_used += removed.len + inserted.len;
        self.cursor = self.patch_count;
        self.enforceBudget();
        return true;
    }

    pub fn canUndo(self: *const UndoStack) bool {
        return self.current_text != null and self.cursor > 0;
    }

    pub fn canRedo(self: *const UndoStack) bool {
        return self.current_text != null and self.cursor < self.patch_count;
    }

    /// Copies the previous state into `output`; returns null at oldest state.
    pub fn undo(self: *UndoStack, output: []u8) !?[]u8 {
        if (!self.canUndo()) return null;
        const patch = self.patches[self.cursor - 1];
        const text = self.current_text.?;
        const new_len = text.len - patch.inserted.len + patch.removed.len;
        if (output.len < new_len) return error.OutputTooSmall;
        try self.applyPatch(patch.offset, patch.inserted.len, patch.removed);
        self.cursor -= 1;
        const now = self.current_text.?;
        @memcpy(output[0..now.len], now);
        return output[0..now.len];
    }

    /// Copies the next state into `output`; returns null at newest state.
    pub fn redo(self: *UndoStack, output: []u8) !?[]u8 {
        if (!self.canRedo()) return null;
        const patch = self.patches[self.cursor];
        const text = self.current_text.?;
        const new_len = text.len - patch.removed.len + patch.inserted.len;
        if (output.len < new_len) return error.OutputTooSmall;
        try self.applyPatch(patch.offset, patch.removed.len, patch.inserted);
        self.cursor += 1;
        const now = self.current_text.?;
        @memcpy(output[0..now.len], now);
        return output[0..now.len];
    }

    pub fn current(self: *const UndoStack) ?[]const u8 {
        return self.current_text;
    }

    /// Number of reachable states (grouped operations + 1 once seeded).
    pub fn entryCount(self: *const UndoStack) usize {
        if (self.current_text == null) return 0;
        return self.patch_count + 1;
    }

    pub fn byteCount(self: *const UndoStack) usize {
        return self.bytes_used;
    }

    /// Replaces `len` bytes at `offset` in the materialized state with
    /// `replacement`, allocating the new buffer before freeing the old one.
    fn applyPatch(self: *UndoStack, offset: usize, len: usize, replacement: []const u8) !void {
        const old = self.current_text.?;
        const new_len = old.len - len + replacement.len;
        const owned = try self.allocator.alloc(u8, new_len);
        @memcpy(owned[0..offset], old[0..offset]);
        @memcpy(owned[offset..][0..replacement.len], replacement);
        @memcpy(owned[offset + replacement.len ..], old[offset + len ..]);
        self.bytes_used -= old.len;
        self.allocator.free(old);
        self.current_text = owned;
        self.bytes_used += owned.len;
    }

    /// Groups keystroke-granularity edits into word-like operations, VS Code
    /// style: single-byte insertions extend the previous insertion run until
    /// a newline, a word boundary (space/tab starting after a non-space), or
    /// the group byte limit; single-byte backspaces extend the previous
    /// removal run the same way. Multi-byte diffs (paste, transforms,
    /// programmatic edits) never coalesce.
    fn tryCoalesce(self: *UndoStack, offset: usize, removed: []u8, inserted: []u8) bool {
        if (self.patch_count == 0 or self.cursor != self.patch_count) return false;
        const prev = &self.patches[self.patch_count - 1];

        // Typing run: one inserted byte continuing the previous insertion.
        if (removed.len == 0 and inserted.len == 1 and prev.removed.len == 0 and
            prev.inserted.len > 0 and offset == prev.offset + prev.inserted.len and
            prev.inserted.len + 1 <= typing_group_limit)
        {
            const byte = inserted[0];
            const prev_last = prev.inserted[prev.inserted.len - 1];
            const breaks_group = byte == '\n' or prev_last == '\n' or
                ((byte == ' ' or byte == '\t') and prev_last != ' ' and prev_last != '\t');
            if (!breaks_group) {
                const merged = self.allocator.alloc(u8, prev.inserted.len + 1) catch return false;
                @memcpy(merged[0..prev.inserted.len], prev.inserted);
                merged[prev.inserted.len] = byte;
                self.bytes_used += 1;
                self.allocator.free(prev.inserted);
                prev.inserted = merged;
                self.allocator.free(removed);
                self.allocator.free(inserted);
                return true;
            }
        }

        // Backspace run: one removed byte ending where the previous starts.
        if (inserted.len == 0 and removed.len == 1 and prev.inserted.len == 0 and
            prev.removed.len > 0 and offset + 1 == prev.offset and
            prev.removed.len + 1 <= typing_group_limit and
            removed[0] != '\n' and prev.removed[0] != '\n')
        {
            const merged = self.allocator.alloc(u8, prev.removed.len + 1) catch return false;
            merged[0] = removed[0];
            @memcpy(merged[1..], prev.removed);
            self.bytes_used += 1;
            self.allocator.free(prev.removed);
            prev.removed = merged;
            prev.offset = offset;
            self.allocator.free(removed);
            self.allocator.free(inserted);
            return true;
        }
        return false;
    }

    /// Drops oldest transitions until the byte budget holds. The materialized
    /// state always fits (record rejects beyond max_bytes), so this converges.
    fn enforceBudget(self: *UndoStack) void {
        while (self.patch_count > 0 and self.bytes_used > self.max_bytes) {
            self.removeOldest();
        }
    }

    fn freePatch(self: *UndoStack, patch: Patch) void {
        self.allocator.free(patch.removed);
        self.allocator.free(patch.inserted);
    }

    fn removeOldest(self: *UndoStack) void {
        std.debug.assert(self.patch_count > 0);
        self.bytes_used -= self.patches[0].cost();
        self.freePatch(self.patches[0]);
        std.mem.copyForwards(Patch, self.patches[0 .. self.patch_count - 1], self.patches[1..self.patch_count]);
        self.patch_count -= 1;
        if (self.cursor > 0) self.cursor -= 1;
    }
};

/// Minimal single-span diff via common prefix/suffix trimming.
fn diffSpan(old: []const u8, new: []const u8) struct {
    offset: usize,
    removed_len: usize,
    inserted_len: usize,
} {
    const min_len = @min(old.len, new.len);
    var prefix: usize = 0;
    while (prefix < min_len and old[prefix] == new[prefix]) : (prefix += 1) {}
    var suffix: usize = 0;
    while (suffix < min_len - prefix and
        old[old.len - 1 - suffix] == new[new.len - 1 - suffix]) : (suffix += 1)
    {}
    return .{
        .offset = prefix,
        .removed_len = old.len - prefix - suffix,
        .inserted_len = new.len - prefix - suffix,
    };
}

test "undo and redo traverse document states" {
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

    _ = try stack.record("one");
    _ = try stack.record("two");
    _ = try stack.record("three");

    var output: [16]u8 = undefined;
    _ = try stack.undo(&output);
    _ = try stack.record("2!");

    try std.testing.expect(!stack.canRedo());
    try std.testing.expectEqualStrings("two", (try stack.undo(&output)).?);
    try std.testing.expectEqualStrings("2!", (try stack.redo(&output)).?);
}

test "keystroke typing coalesces into word-grouped operations" {
    var stack = try UndoStack.init(std.testing.allocator, .{});
    defer stack.deinit();

    // Simulate typing "fn main" one keystroke at a time (per-edit records).
    const doc = "fn main";
    var len: usize = 1;
    _ = try stack.record(doc[0..len]);
    while (len < doc.len) : (len += 1) {
        _ = try stack.record(doc[0 .. len + 1]);
    }

    // Grouped at the word boundary: seed "f", run "n", run " main" - so an
    // undo removes a word-like chunk, not one character.
    try std.testing.expectEqual(@as(usize, 3), stack.entryCount());
    var output: [64]u8 = undefined;
    try std.testing.expectEqualStrings("fn", (try stack.undo(&output)).?);
    try std.testing.expectEqualStrings("f", (try stack.undo(&output)).?);
    try std.testing.expectEqualStrings("fn", (try stack.redo(&output)).?);
    try std.testing.expectEqualStrings("fn main", (try stack.redo(&output)).?);
}

test "newlines break typing groups" {
    var stack = try UndoStack.init(std.testing.allocator, .{});
    defer stack.deinit();

    _ = try stack.record("ab");
    _ = try stack.record("abc");
    _ = try stack.record("abc\n");
    _ = try stack.record("abc\nd");
    _ = try stack.record("abc\nde");

    // Groups: seed "ab", "c", "\n", "de" - the newline is its own operation.
    try std.testing.expectEqual(@as(usize, 4), stack.entryCount());
    var output: [64]u8 = undefined;
    try std.testing.expectEqualStrings("abc\n", (try stack.undo(&output)).?);
    try std.testing.expectEqualStrings("abc", (try stack.undo(&output)).?);
    try std.testing.expectEqualStrings("ab", (try stack.undo(&output)).?);
}

test "backspace runs coalesce into one grouped operation" {
    var stack = try UndoStack.init(std.testing.allocator, .{});
    defer stack.deinit();

    _ = try stack.record("abcdef");
    _ = try stack.record("abcde");
    _ = try stack.record("abcd");
    _ = try stack.record("abc");

    try std.testing.expectEqual(@as(usize, 2), stack.entryCount());
    var output: [16]u8 = undefined;
    try std.testing.expectEqualStrings("abcdef", (try stack.undo(&output)).?);
}

test "history memory stays proportional to edits, not document size" {
    var stack = try UndoStack.init(std.testing.allocator, .{ .max_bytes = 64 * 1024 });
    defer stack.deinit();

    // A 16 KiB document plus many small distinct edits must fit comfortably
    // in a budget that could hold only four full snapshots.
    const base = try std.testing.allocator.alloc(u8, 16 * 1024);
    defer std.testing.allocator.free(base);
    @memset(base, 'x');

    var doc = try std.testing.allocator.alloc(u8, base.len + 32);
    defer std.testing.allocator.free(doc);
    @memcpy(doc[0..base.len], base);

    _ = try stack.record(base);
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        doc[base.len + i] = @intCast('a' + (i % 26));
        if (i % 2 == 1) doc[base.len + i] = '\n'; // break groups
        _ = try stack.record(doc[0 .. base.len + i + 1]);
    }
    // 21 states reachable; snapshot storage would need ~336 KiB.
    try std.testing.expectEqual(@as(usize, 21), stack.entryCount());
    try std.testing.expect(stack.byteCount() < 20 * 1024);

    var output: [17 * 1024]u8 = undefined;
    var undone: usize = 0;
    while ((try stack.undo(&output)) != null) undone += 1;
    try std.testing.expectEqual(@as(usize, 20), undone);
    try std.testing.expectEqualStrings(base, stack.current().?);
}

test "budgets evict oldest operations and reject oversized states" {
    var stack = try UndoStack.init(std.testing.allocator, .{ .max_entries = 3, .max_bytes = 16 });
    defer stack.deinit();

    _ = try stack.record("11\n1");
    _ = try stack.record("22\n2");
    _ = try stack.record("33\n3");
    _ = try stack.record("44\n4");

    // max_entries caps transitions; the oldest states become unreachable.
    var output: [16]u8 = undefined;
    var undone: usize = 0;
    while ((try stack.undo(&output)) != null) undone += 1;
    try std.testing.expect(undone <= 3);
    try std.testing.expectError(error.SnapshotTooLarge, stack.record("12345678901234567"));
}

test "small output leaves history position unchanged" {
    var stack = try UndoStack.init(std.testing.allocator, .{});
    defer stack.deinit();

    _ = try stack.record("short");
    _ = try stack.record("a much longer state\n");

    var small: [2]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, stack.undo(&small));
    try std.testing.expect(stack.canUndo());
    try std.testing.expectEqualStrings("a much longer state\n", stack.current().?);
}

test "clear releases everything and stack remains usable" {
    var stack = try UndoStack.init(std.testing.allocator, .{});
    defer stack.deinit();

    _ = try stack.record("alpha");
    _ = try stack.record("alpha beta");
    stack.clear();
    try std.testing.expectEqual(@as(usize, 0), stack.entryCount());
    try std.testing.expectEqual(@as(usize, 0), stack.byteCount());
    try std.testing.expect(!stack.canUndo());

    _ = try stack.record("fresh");
    try std.testing.expectEqualStrings("fresh", stack.current().?);
}
