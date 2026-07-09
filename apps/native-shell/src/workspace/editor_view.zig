//! Editor view helpers — line focus context peek (textarea has no caret API yet).

const std = @import("std");

pub const max_peek_lines: usize = 7;
pub const max_peek_bytes: usize = 512;
pub const max_gutter_rows: usize = 48;

pub const PeekLine = struct {
    id: u32 = 0,
    text: []const u8 = "",
    is_focus: bool = false,
};

/// Build a short context window around `focus_line` (1-based).
pub fn buildPeek(
    text: []const u8,
    focus_line: u32,
    out_lines: []PeekLine,
    pool: []u8,
    pool_lens: []usize,
) u32 {
    if (focus_line == 0 or out_lines.len == 0) return 0;
    var total: u32 = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            total += 1;
            start = i + 1;
        }
    }
    if (total == 0) return 0;
    const focus = @min(focus_line, total);
    const radius: u32 = 3;
    const from: u32 = if (focus > radius) focus - radius else 1;
    const to: u32 = @min(total, focus + radius);

    var count: u32 = 0;
    var pool_used: usize = 0;
    var line_no: u32 = 1;
    start = 0;
    i = 0;
    while (i <= text.len and count < out_lines.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            if (line_no >= from and line_no <= to) {
                const raw = text[start..i];
                const marker: []const u8 = if (line_no == focus) "> " else "  ";
                var line_buf: [160]u8 = undefined;
                const formatted = std.fmt.bufPrint(&line_buf, "{s}{d:>4}  {s}", .{ marker, line_no, raw }) catch raw;
                const n = @min(formatted.len, pool.len - pool_used);
                if (n == 0) break;
                @memcpy(pool[pool_used..][0..n], formatted[0..n]);
                pool_lens[count] = n;
                out_lines[count] = .{
                    .id = line_no,
                    .text = pool[pool_used .. pool_used + n],
                    .is_focus = line_no == focus,
                };
                pool_used += n;
                count += 1;
            }
            line_no += 1;
            start = i + 1;
        }
    }
    return count;
}

test "peek highlights focus line" {
    var lines: [8]PeekLine = undefined;
    var pool: [512]u8 = undefined;
    var lens: [8]usize = undefined;
    const n = buildPeek("a\nb\nc\nd\ne\n", 3, &lines, &pool, &lens);
    try std.testing.expect(n >= 3);
    var found = false;
    for (lines[0..n]) |l| {
        if (l.is_focus) {
            found = true;
            try std.testing.expect(std.mem.indexOf(u8, l.text, "> ") != null);
        }
    }
    try std.testing.expect(found);
}
