//! Lightweight prefs persistence (theme, last workspace path, recent list).
//! Writes a tiny key=value file under .velocity/prefs.txt relative to cwd.

const std = @import("std");

pub const max_recent: usize = 5;
pub const max_path: usize = 240;
pub const prefs_rel_path = ".velocity/prefs.txt";

pub const Prefs = struct {
    theme: []const u8 = "dark",
    last_path: []const u8 = "",
    show_terminal: bool = true,
    show_agent: bool = true,
    auto_save: bool = false,
    find_case_sensitive: bool = false,
    find_whole_word: bool = false,
    search_case_sensitive: bool = false,
    show_sidebar: bool = true,
    trim_trailing_ws: bool = false,
    insert_final_newline: bool = true,
    indent_size: u8 = 2,
    recent_count: u32 = 0,
    recent_paths: [max_recent][max_path]u8 = undefined,
    recent_lens: [max_recent]usize = [_]usize{0} ** max_recent,
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

    pub fn setTheme(self: *Prefs, theme_name: []const u8) void {
        const n = @min(theme_name.len, self.theme_buf.len);
        @memcpy(self.theme_buf[0..n], theme_name[0..n]);
        self.theme_len = n;
        self.theme = self.themeSlice();
    }

    pub fn setLastPath(self: *Prefs, path: []const u8) void {
        const n = @min(path.len, self.last_path_buf.len);
        @memcpy(self.last_path_buf[0..n], path[0..n]);
        self.last_path_len = n;
        self.last_path = self.lastPathSlice();
        self.pushRecent(path);
    }

    pub fn pushRecent(self: *Prefs, path: []const u8) void {
        if (path.len == 0) return;
        var i: u32 = 0;
        while (i < self.recent_count) : (i += 1) {
            if (std.mem.eql(u8, self.recentPath(i), path)) {
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
        const n = @min(path.len, max_path);
        @memcpy(self.recent_paths[0][0..n], path[0..n]);
        self.recent_lens[0] = n;
        self.recent_count += 1;
    }

    pub fn load(self: *Prefs, io: std.Io) void {
        self.* = .{};
        self.setTheme("dark");
        var buf: [4096]u8 = undefined;
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
    }

    fn parseLine(self: *Prefs, line: []const u8) void {
        if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
            const key = line[0..eq];
            const val = line[eq + 1 ..];
            if (std.mem.eql(u8, key, "theme")) self.setTheme(val);
            if (std.mem.eql(u8, key, "last_path")) self.setLastPath(val);
            if (std.mem.eql(u8, key, "show_terminal")) self.show_terminal = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "show_agent")) self.show_agent = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "auto_save")) self.auto_save = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "find_case_sensitive")) self.find_case_sensitive = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "find_whole_word")) self.find_whole_word = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "search_case_sensitive")) self.search_case_sensitive = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "show_sidebar")) self.show_sidebar = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "trim_trailing_ws")) self.trim_trailing_ws = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "insert_final_newline")) self.insert_final_newline = std.mem.eql(u8, val, "1");
            if (std.mem.eql(u8, key, "indent_size")) {
                if (std.fmt.parseInt(u8, val, 10)) |n| {
                    if (n == 2 or n == 4) self.indent_size = n;
                } else |_| {}
            }
            if (std.mem.startsWith(u8, key, "recent")) self.pushRecent(val);
        }
    }

    pub fn save(self: *const Prefs, io: std.Io) void {
        var out: [2048]u8 = undefined;
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
        append(&out, &len, "\nshow_sidebar=");
        append(&out, &len, if (self.show_sidebar) "1" else "0");
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
        std.Io.Dir.cwd().createDirPath(io, ".velocity") catch {};
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = prefs_rel_path, .data = out[0..len] }) catch {};
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
    p.show_sidebar = false;
    p.trim_trailing_ws = true;
    p.insert_final_newline = false;
    p.indent_size = 4;
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
    try std.testing.expect(!p2.show_sidebar);
    try std.testing.expect(p2.trim_trailing_ws);
    try std.testing.expect(!p2.insert_final_newline);
    try std.testing.expectEqual(@as(u8, 4), p2.indent_size);
    std.Io.Dir.cwd().deleteTree(std.testing.io, ".velocity") catch {};
}
