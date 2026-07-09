//! Find-in-document — locate matches in the active editor buffer.

const std = @import("std");

pub const max_matches: usize = 128;
pub const max_query: usize = 64;
pub const max_preview: usize = 80;

pub const DocMatch = struct {
    id: u32 = 0,
    line: u32 = 0,
    column: u32 = 0,
    preview: []const u8 = "",
};

pub const FindBuffers = struct {
    matches: [max_matches]DocMatch = [_]DocMatch{.{}} ** max_matches,
    match_count: u32 = 0,
    preview_pool: [max_matches][max_preview]u8 = undefined,
    preview_lens: [max_matches]usize = [_]usize{0} ** max_matches,
    active_index: u32 = 0,
    status: []const u8 = "idle",

    pub fn matchesSlice(self: *FindBuffers) []const DocMatch {
        return self.matches[0..self.match_count];
    }

    pub fn clear(self: *FindBuffers) void {
        self.match_count = 0;
        self.active_index = 0;
        self.status = "idle";
    }

    pub fn find(self: *FindBuffers, text: []const u8, query: []const u8) void {
        self.clear();
        if (query.len == 0) {
            self.status = "empty query";
            return;
        }
        var line_no: u32 = 1;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= text.len and self.match_count < max_matches) : (i += 1) {
            if (i == text.len or text[i] == '\n') {
                const line = text[start..i];
                var search_from: usize = 0;
                while (search_from < line.len and self.match_count < max_matches) {
                    if (std.ascii.indexOfIgnoreCase(line[search_from..], query)) |rel| {
                        const col = search_from + rel;
                        self.pushMatch(line_no, @intCast(col + 1), line);
                        search_from = col + query.len;
                        if (query.len == 0) break;
                    } else break;
                }
                line_no += 1;
                start = i + 1;
            }
        }
        self.status = if (self.match_count == 0) "no matches" else "done";
        self.active_index = 0;
    }

    pub fn next(self: *FindBuffers) void {
        if (self.match_count == 0) return;
        self.active_index = (self.active_index + 1) % self.match_count;
    }

    pub fn prev(self: *FindBuffers) void {
        if (self.match_count == 0) return;
        if (self.active_index == 0) self.active_index = self.match_count - 1 else self.active_index -= 1;
    }

    pub fn activeMatch(self: *const FindBuffers) ?DocMatch {
        if (self.match_count == 0) return null;
        return self.matches[self.active_index];
    }

    fn pushMatch(self: *FindBuffers, line: u32, column: u32, preview_src: []const u8) void {
        const idx = self.match_count;
        const trimmed = std.mem.trim(u8, preview_src, " \t\r");
        const vlen = @min(trimmed.len, self.preview_pool[idx].len);
        @memcpy(self.preview_pool[idx][0..vlen], trimmed[0..vlen]);
        self.preview_lens[idx] = vlen;
        self.matches[idx] = .{
            .id = idx + 1,
            .line = line,
            .column = column,
            .preview = self.preview_pool[idx][0..vlen],
        };
        self.match_count += 1;
    }
};

test "find locates multiple matches" {
    var f: FindBuffers = .{};
    f.find("hello\nworld hello\nbye", "hello");
    try std.testing.expect(f.match_count == 2);
    try std.testing.expect(f.matches[0].line == 1);
    try std.testing.expect(f.matches[1].line == 2);
}
