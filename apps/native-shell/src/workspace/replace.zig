//! In-document replace helpers (MVP).

const std = @import("std");

pub const max_out = 16 * 1024;

pub const ReplaceResult = struct {
    count: u32 = 0,
    out_len: usize = 0,
};

/// Replace first occurrence of `find` with `repl` into `out`. Returns false if not found.
pub fn replaceOnce(text: []const u8, find: []const u8, repl: []const u8, out: []u8) ?ReplaceResult {
    if (find.len == 0) return null;
    const idx = std.mem.indexOf(u8, text, find) orelse return null;
    const need = text.len - find.len + repl.len;
    if (need > out.len) return null;
    @memcpy(out[0..idx], text[0..idx]);
    @memcpy(out[idx..][0..repl.len], repl);
    @memcpy(out[idx + repl.len ..][0 .. text.len - idx - find.len], text[idx + find.len ..]);
    return .{ .count = 1, .out_len = need };
}

/// Replace all non-overlapping occurrences.
pub fn replaceAll(text: []const u8, find: []const u8, repl: []const u8, out: []u8) ?ReplaceResult {
    if (find.len == 0) return null;
    var count: u32 = 0;
    var src_i: usize = 0;
    var dst_i: usize = 0;
    while (src_i < text.len) {
        if (std.mem.startsWith(u8, text[src_i..], find)) {
            if (dst_i + repl.len > out.len) return null;
            @memcpy(out[dst_i..][0..repl.len], repl);
            dst_i += repl.len;
            src_i += find.len;
            count += 1;
        } else {
            if (dst_i + 1 > out.len) return null;
            out[dst_i] = text[src_i];
            dst_i += 1;
            src_i += 1;
        }
    }
    if (count == 0) return null;
    return .{ .count = count, .out_len = dst_i };
}

test "replace once and all" {
    var out: [64]u8 = undefined;
    const once = replaceOnce("a foo b foo", "foo", "bar", &out).?;
    try std.testing.expect(once.count == 1);
    try std.testing.expectEqualStrings("a bar b foo", out[0..once.out_len]);
    const all = replaceAll("a foo b foo", "foo", "bar", &out).?;
    try std.testing.expect(all.count == 2);
    try std.testing.expectEqualStrings("a bar b bar", out[0..all.out_len]);
}
