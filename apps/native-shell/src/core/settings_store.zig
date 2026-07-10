//! Search metadata for the actual preferences persisted by `prefs.zig`.

const prefs = @import("prefs.zig");

pub const Kind = enum { boolean, choice, duration, text };

pub const Entry = struct {
    key: []const u8,
    label: []const u8,
    keywords: []const u8,
    kind: Kind,
};

pub const entries = [_]Entry{
    .{ .key = "theme", .label = "Color Theme", .keywords = "appearance dark light contrast", .kind = .choice },
    .{ .key = "find_case_sensitive", .label = "Find: Match Case", .keywords = "editor search case sensitive", .kind = .boolean },
    .{ .key = "find_whole_word", .label = "Find: Match Whole Word", .keywords = "editor search word", .kind = .boolean },
    .{ .key = "search_case_sensitive", .label = "Workspace Search: Match Case", .keywords = "search case sensitive persisted", .kind = .boolean },
    .{ .key = "search_whole_word", .label = "Workspace Search: Match Whole Word", .keywords = "search whole word persisted", .kind = .boolean },
    .{ .key = "disk_poll_interval_ms", .label = "Files: Disk Poll Interval", .keywords = "workspace files reload polling milliseconds", .kind = .duration },
    .{ .key = "auto_save", .label = "Files: Auto Save", .keywords = "workspace editor save", .kind = .boolean },
    .{ .key = "word_wrap", .label = "Editor: Word Wrap", .keywords = "editor wrap", .kind = .boolean },
};

pub fn defaultDiskPollIntervalMs() u32 {
    return prefs.default_disk_poll_interval_ms;
}

test "settings metadata indexes actual persisted preference keys" {
    inline for (entries) |entry| {
        if (!@hasField(prefs.Prefs, entry.key)) @compileError("settings metadata key is not in Prefs");
    }
}
