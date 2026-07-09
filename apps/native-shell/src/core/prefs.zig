//! Lightweight prefs persistence for durable shell and editor state.
//! Writes a tiny key=value file under .velocity/prefs.txt relative to cwd.

const std = @import("std");
const scanner = @import("../workspace/scanner.zig");

pub const max_recent: usize = 5;
pub const max_recent_files: usize = 8;
pub const max_path: usize = 240;
pub const max_prefs_bytes: usize = 8192;
pub const prefs_rel_path = ".velocity/prefs.txt";
pub const default_disk_poll_interval_ms: u32 = 2000;

pub const BottomPanelTab = enum {
    terminal,
    output,
    problems,
};

pub const Prefs = struct {
    theme: []const u8 = "dark",
    last_path: []const u8 = "",
    show_terminal: bool = false,
    show_agent: bool = false,
    auto_save: bool = false,
    find_case_sensitive: bool = false,
    find_whole_word: bool = false,
    search_case_sensitive: bool = false,
    search_whole_word: bool = false,
    show_sidebar: bool = true,
    focus_mode: bool = false,
    bottom_panel_open: bool = false,
    bottom_panel_tab: BottomPanelTab = .terminal,
    disk_poll_interval_ms: u32 = default_disk_poll_interval_ms,
    word_wrap: bool = false,
    trim_trailing_ws: bool = false,
    insert_final_newline: bool = true,
    indent_size: u8 = 2,
    recent_count: u32 = 0,
    recent_paths: [max_recent][max_path]u8 = undefined,
    recent_lens: [max_recent]usize = [_]usize{0} ** max_recent,
    recent_file_count: u32 = 0,
    recent_files: [max_recent_files][max_path]u8 = undefined,
    recent_file_lens: [max_recent_files]usize = [_]usize{0} ** max_recent_files,
    theme_buf: [16]u8 = undefined,
    theme_len: usize = 0,
    last_path_buf: [max_path]u8 = undefined,
    last_path_len: usize = 0,

    pub fn themeSlice(self: *const Prefs) []const u8 {
        return self.theme_buf[0..self.theme_len];
    }

    pub fn lastPathSlice(self: *const Prefs) []const u8 {
        return self.last_path_buf[0..self.last_path_len];
    }

    pub fn recentPath(self: *const Prefs, i: u32) []const u8 {
        if (i >= self.recent_count) return "";
        return self.recent_paths[i][0..self.recent_lens[i]];
    }

    pub fn recentFile(self: *const Prefs, i: u32) []const u8 {
        if (i >= self.recent_file_count) return "";
        return self.recent_files[i][0..self.recent_file_lens[i]];
    }

    pub fn setTheme(self: *Prefs, theme_name: []const u8) void {
        const n = @min(theme_name.len, self.theme_buf.len);
        @memcpy(self.theme_buf[0..n], theme_name[0..n]);
        self.theme_len = n;
        self.theme = self.themeSlice();
    }

    pub fn setLastPath(self: *Prefs, path: []const u8) void {
        self.setLastPathOnly(path);
        self.pushRecent(path);
    }

    fn setLastPathOnly(self: *Prefs, path: []const u8) void {
        const n = @min(path.len, self.last_path_buf.len);
        @memcpy(self.last_path_buf[0..n], path[0..n]);
        self.last_path_len = n;
        self.last_path = self.lastPathSlice();
    }

    pub fn pushRecent(self: *Prefs, path: []const u8) void {
        if (path.len == 0) return;
        const bounded_path = path[0..@min(path.len, max_path)];
        var i: u32 = 0;
        while (i < self.recent_count) : (i += 1) {
            if (std.mem.eql(u8, self.recentPath(i), bounded_path)) {
                var j = i;
                while (j + 1 < self.recent_count) : (j += 1) {
                    const len = self.recent_lens[j + 1];
                    @memcpy(self.recent_paths[j][0..len], self.recent_paths[j + 1][0..len]);
                    self.recent_lens[j] = len;
                }
                self.recent_count -= 1;
                break;
            }
        }
        if (self.recent_count >= max_recent) {
            self.recent_count = max_recent - 1;
        }
        var k = self.recent_count;
        while (k > 0) : (k -= 1) {
            const len = self.recent_lens[k - 1];
            @memcpy(self.recent_paths[k][0..len], self.recent_paths[k - 1][0..len]);
            self.recent_lens[k] = len;
        }
        const n = bounded_path.len;
        @memcpy(self.recent_paths[0][0..n], bounded_path);
        self.recent_lens[0] = n;
        self.recent_count += 1;
    }

    pub fn pushRecentFile(self: *Prefs, path: []const u8) void {
        if (path.len == 0) return;
        const bounded_path = path[0..@min(path.len, max_path)];
        var i: u32 = 0;
        while (i < self.recent_file_count) : (i += 1) {
            if (std.mem.eql(u8, self.recentFile(i), bounded_path)) {
                var j = i;
                while (j + 1 < self.recent_file_count) : (j += 1) {
                    const len = self.recent_file_lens[j + 1];
                    @memcpy(self.recent_files[j][0..len], self.recent_files[j + 1][0..len]);
                    self.recent_file_lens[j] = len;
                }
                self.recent_file_count -= 1;
                break;
            }
        }
        if (self.recent_file_count >= max_recent_files) {
            self.recent_file_count = max_recent_files - 1;
        }
        var k = self.recent_file_count;
        while (k > 0) : (k -= 1) {
            const len = self.recent_file_lens[k - 1];
            @memcpy(self.recent_files[k][0..len], self.recent_files[k - 1][0..len]);
            self.recent_file_lens[k] = len;
        }
        @memcpy(self.recent_files[0][0..bounded_path.len], bounded_path);
        self.recent_file_lens[0] = bounded_path.len;
        self.recent_file_count += 1;
    }

    fn appendRecent(self: *Prefs, path: []const u8) void {
        if (path.len == 0 or self.recent_count >= max_recent) return;
        const bounded_path = path[0..@min(path.len, max_path)];
        var i: u32 = 0;
        while (i < self.recent_count) : (i += 1) {
            if (std.mem.eql(u8, self.recentPath(i), bounded_path)) return;
        }
        const index = self.recent_count;
        @memcpy(self.recent_paths[index][0..bounded_path.len], bounded_path);
        self.recent_lens[index] = bounded_path.len;
        self.recent_count += 1;
    }

    fn appendRecentFile(self: *Prefs, path: []const u8) void {
        if (path.len == 0 or self.recent_file_count >= max_recent_files) return;
        const bounded_path = path[0..@min(path.len, max_path)];
        var i: u32 = 0;
        while (i < self.recent_file_count) : (i += 1) {
            if (std.mem.eql(u8, self.recentFile(i), bounded_path)) return;
        }
        const index = self.recent_file_count;
        @memcpy(self.recent_files[index][0..bounded_path.len], bounded_path);
        self.recent_file_lens[index] = bounded_path.len;
        self.recent_file_count += 1;
    }

    pub fn clearRecent(self: *Prefs) void {
        self.recent_count = 0;
        self.last_path_len = 0;
        self.last_path = "";
    }

    pub fn load(self: *Prefs, io: std.Io) void {
        self.* = .{};
        self.setTheme("dark");
        var buf: [max_prefs_bytes]u8 = undefined;
        const data = std.Io.Dir.cwd().readFile(io, prefs_rel_path, &buf) catch return;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= data.len) : (i += 1) {
            if (i == data.len or data[i] == '\n') {
                const line = std.mem.trim(u8, data[start..i], " \t\r");
                if (line.len > 0) self.parseLine(line);
                start = i + 1;
            }
        }
        if (self.recent_count == 0 and self.last_path_len > 0) {
            self.appendRecent(self.lastPathSlice());
        }
    }

    fn parseLine(self: *Prefs, line: []const u8) void {
        if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
            const key = line[0..eq];
            const val = line[eq + 1 ..];
            if (std.mem.eql(u8, key, "theme")) self.setTheme(val);
            if (std.mem.eql(u8, key, "last_path")) self.setLastPathOnly(val);
            if (std.mem.eql(u8, key, "show_terminal")) self.show_terminal = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "show_agent")) self.show_agent = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "auto_save")) self.auto_save = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "find_case_sensitive")) self.find_case_sensitive = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "find_whole_word")) self.find_whole_word = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "search_case_sensitive")) self.search_case_sensitive = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "search_whole_word")) self.search_whole_word = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "show_sidebar")) self.show_sidebar = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "focus_mode")) self.focus_mode = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "bottom_panel_open")) self.bottom_panel_open = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "bottom_panel_tab")) {
                self.bottom_panel_tab = std.meta.stringToEnum(BottomPanelTab, val) orelse .terminal;
            }
            if (std.mem.eql(u8, key, "disk_poll_interval_ms")) {
                if (std.fmt.parseInt(u32, val, 10)) |n| {
                    if (n > 0) self.disk_poll_interval_ms = n;
                } else |_| {}
            }
            if (std.mem.eql(u8, key, "word_wrap")) self.word_wrap = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "trim_trailing_ws")) self.trim_trailing_ws = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "insert_final_newline")) self.insert_final_newline = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "indent_size")) {
                if (std.fmt.parseInt(u8, val, 10)) |n| {
                    if (n == 2 or n == 4) self.indent_size = n;
                } else |_| {}
            }
            if (std.mem.eql(u8, key, "recent") or std.mem.eql(u8, key, "recent_project")) self.appendRecent(val);
            if (std.mem.eql(u8, key, "recent_file")) self.appendRecentFile(val);
        }
    }

    pub fn save(self: *const Prefs, io: std.Io) void {
        var out: [max_prefs_bytes]u8 = undefined;
        var len: usize = 0;
        const append = struct {
            fn go(buf: []u8, used: *usize, piece: []const u8) void {
                const n = @min(piece.len, buf.len - used.*);
                @memcpy(buf[used.*..][0..n], piece[0..n]);
                used.* += n;
            }
        }.go;

        append(&out, &len, "theme=");
        append(&out, &len, self.themeSlice());
        append(&out, &len, "\nlast_path=");
        append(&out, &len, self.lastPathSlice());
        append(&out, &len, "\nshow_terminal=");
        append(&out, &len, if (self.show_terminal) "1" else "0");
        append(&out, &len, "\nshow_agent=");
        append(&out, &len, if (self.show_agent) "1" else "0");
        append(&out, &len, "\nauto_save=");
        append(&out, &len, if (self.auto_save) "1" else "0");
        append(&out, &len, "\nfind_case_sensitive=");
        append(&out, &len, if (self.find_case_sensitive) "1" else "0");
        append(&out, &len, "\nfind_whole_word=");
        append(&out, &len, if (self.find_whole_word) "1" else "0");
        append(&out, &len, "\nsearch_case_sensitive=");
        append(&out, &len, if (self.search_case_sensitive) "1" else "0");
        append(&out, &len, "\nsearch_whole_word=");
        append(&out, &len, if (self.search_whole_word) "1" else "0");
        append(&out, &len, "\nshow_sidebar=");
        append(&out, &len, if (self.show_sidebar) "1" else "0");
        append(&out, &len, "\nfocus_mode=");
        append(&out, &len, if (self.focus_mode) "1" else "0");
        append(&out, &len, "\nbottom_panel_open=");
        append(&out, &len, if (self.bottom_panel_open) "1" else "0");
        append(&out, &len, "\nbottom_panel_tab=");
        append(&out, &len, @tagName(self.bottom_panel_tab));
        append(&out, &len, "\ndisk_poll_interval_ms=");
        var poll_buf: [10]u8 = undefined;
        const poll_s = std.fmt.bufPrint(&poll_buf, "{d}", .{self.disk_poll_interval_ms}) catch "2000";
        append(&out, &len, poll_s);
        append(&out, &len, "\nword_wrap=");
        append(&out, &len, if (self.word_wrap) "1" else "0");
        append(&out, &len, "\ntrim_trailing_ws=");
        append(&out, &len, if (self.trim_trailing_ws) "1" else "0");
        append(&out, &len, "\ninsert_final_newline=");
        append(&out, &len, if (self.insert_final_newline) "1" else "0");
        append(&out, &len, "\nindent_size=");
        var indent_buf: [4]u8 = undefined;
        const indent_s = std.fmt.bufPrint(&indent_buf, "{d}", .{self.indent_size}) catch "2";
        append(&out, &len, indent_s);
        append(&out, &len, "\n");
        var i: u32 = 0;
        while (i < self.recent_count) : (i += 1) {
            append(&out, &len, "recent=");
            append(&out, &len, self.recentPath(i));
            append(&out, &len, "\n");
        }
        i = 0;
        while (i < self.recent_file_count) : (i += 1) {
            append(&out, &len, "recent_file=");
            append(&out, &len, self.recentFile(i));
            append(&out, &len, "\n");
        }
        scanner.writeFileAtomic(io, ".", prefs_rel_path, out[0..len], max_prefs_bytes) catch {};
    }
};

test "prefs roundtrip theme and recent" {
    var p: Prefs = .{};
    p.setTheme("light");
    p.setLastPath("fixtures/acme-dashboard");
    p.show_terminal = false;
    p.auto_save = true;
    p.find_case_sensitive = true;
    p.find_whole_word = true;
    p.search_case_sensitive = true;
    p.search_whole_word = true;
    p.show_sidebar = false;
    p.focus_mode = true;
    p.bottom_panel_open = true;
    p.bottom_panel_tab = .problems;
    p.disk_poll_interval_ms = 750;
    p.word_wrap = true;
    p.trim_trailing_ws = true;
    p.insert_final_newline = false;
    p.indent_size = 4;
    p.pushRecent("fixtures/empty");
    p.pushRecentFile("src/main.zig");
    p.pushRecentFile("src/core/prefs.zig");
    p.save(std.testing.io);
    var p2: Prefs = .{};
    p2.load(std.testing.io);
    try std.testing.expectEqualStrings("light", p2.themeSlice());
    try std.testing.expectEqualStrings("fixtures/acme-dashboard", p2.lastPathSlice());
    try std.testing.expect(!p2.show_terminal);
    try std.testing.expect(p2.auto_save);
    try std.testing.expect(p2.find_case_sensitive);
    try std.testing.expect(p2.find_whole_word);
    try std.testing.expect(p2.search_case_sensitive);
    try std.testing.expect(p2.search_whole_word);
    try std.testing.expect(!p2.show_sidebar);
    try std.testing.expect(p2.focus_mode);
    try std.testing.expect(p2.bottom_panel_open);
    try std.testing.expectEqual(BottomPanelTab.problems, p2.bottom_panel_tab);
    try std.testing.expectEqual(@as(u32, 750), p2.disk_poll_interval_ms);
    try std.testing.expect(p2.word_wrap);
    try std.testing.expect(p2.trim_trailing_ws);
    try std.testing.expect(!p2.insert_final_newline);
    try std.testing.expectEqual(@as(u8, 4), p2.indent_size);
    try std.testing.expectEqual(@as(u32, 2), p2.recent_count);
    try std.testing.expectEqualStrings("fixtures/empty", p2.recentPath(0));
    try std.testing.expectEqualStrings("fixtures/acme-dashboard", p2.recentPath(1));
    try std.testing.expectEqual(@as(u32, 2), p2.recent_file_count);
    try std.testing.expectEqualStrings("src/core/prefs.zig", p2.recentFile(0));
    try std.testing.expectEqualStrings("src/main.zig", p2.recentFile(1));
    std.Io.Dir.cwd().deleteTree(std.testing.io, ".velocity") catch {};
}
