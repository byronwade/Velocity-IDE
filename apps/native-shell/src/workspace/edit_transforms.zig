//! Lightweight document transforms for the native textarea MVP.
//! Whole-document operations (no selection API yet).

const std = @import("std");

pub const max_out = 16 * 1024;

fn commentPrefixFor(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".py") or std.mem.endsWith(u8, path, ".sh") or std.mem.endsWith(u8, path, ".yaml") or std.mem.endsWith(u8, path, ".yml") or std.mem.endsWith(u8, path, ".toml")) {
        return "# ";
    }
    if (std.mem.endsWith(u8, path, ".html") or std.mem.endsWith(u8, path, ".xml") or std.mem.endsWith(u8, path, ".svg")) {
        return "<!-- ";
    }
    // Default C-like
    return "// ";
}

fn lineIsCommented(line: []const u8, prefix: []const u8) bool {
    const trimmed = std.mem.trimStart(u8, line, " \t");
    return std.mem.startsWith(u8, trimmed, prefix);
}

/// Toggle line comments on every non-empty line. If majority already commented, uncomment.
pub fn toggleLineComments(text: []const u8, path: []const u8, out: []u8) ?usize {
    const prefix = commentPrefixFor(path);
    const html_close = " -->";
    const is_html = std.mem.eql(u8, prefix, "<!-- ");

    var total_nonempty: u32 = 0;
    var commented: u32 = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            const line = text[start..i];
            if (std.mem.trim(u8, line, " \t\r").len > 0) {
                total_nonempty += 1;
                if (lineIsCommented(line, prefix)) commented += 1;
            }
            start = i + 1;
        }
    }
    const should_uncomment = total_nonempty > 0 and commented * 2 >= total_nonempty;

    var dst: usize = 0;
    start = 0;
    i = 0;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            const line = text[start..i];
            const trimmed_left = std.mem.trimStart(u8, line, " \t");
            const lead_len = line.len - trimmed_left.len;

            if (std.mem.trim(u8, line, " \t\r").len == 0) {
                if (dst + line.len > out.len) return null;
                @memcpy(out[dst..][0..line.len], line);
                dst += line.len;
            } else if (should_uncomment and lineIsCommented(line, prefix)) {
                // Keep leading whitespace, drop prefix (+ optional html close).
                if (dst + lead_len > out.len) return null;
                @memcpy(out[dst..][0..lead_len], line[0..lead_len]);
                dst += lead_len;
                var body = trimmed_left[prefix.len..];
                if (is_html and std.mem.endsWith(u8, body, html_close)) {
                    body = body[0 .. body.len - html_close.len];
                }
                if (dst + body.len > out.len) return null;
                @memcpy(out[dst..][0..body.len], body);
                dst += body.len;
            } else if (!should_uncomment) {
                if (dst + lead_len + prefix.len + trimmed_left.len + (if (is_html) html_close.len else 0) > out.len) return null;
                @memcpy(out[dst..][0..lead_len], line[0..lead_len]);
                dst += lead_len;
                @memcpy(out[dst..][0..prefix.len], prefix);
                dst += prefix.len;
                @memcpy(out[dst..][0..trimmed_left.len], trimmed_left);
                dst += trimmed_left.len;
                if (is_html) {
                    @memcpy(out[dst..][0..html_close.len], html_close);
                    dst += html_close.len;
                }
            } else {
                if (dst + line.len > out.len) return null;
                @memcpy(out[dst..][0..line.len], line);
                dst += line.len;
            }

            if (i < text.len) {
                if (dst + 1 > out.len) return null;
                out[dst] = '\n';
                dst += 1;
            }
            start = i + 1;
        }
    }
    return dst;
}

pub fn indentLines(text: []const u8, spaces: u8, out: []u8) ?usize {
    const pad = spaces;
    var dst: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            const line = text[start..i];
            if (std.mem.trim(u8, line, " \t\r").len > 0) {
                if (dst + pad + line.len > out.len) return null;
                var p: u8 = 0;
                while (p < pad) : (p += 1) {
                    out[dst] = ' ';
                    dst += 1;
                }
                @memcpy(out[dst..][0..line.len], line);
                dst += line.len;
            } else {
                if (dst + line.len > out.len) return null;
                @memcpy(out[dst..][0..line.len], line);
                dst += line.len;
            }
            if (i < text.len) {
                if (dst + 1 > out.len) return null;
                out[dst] = '\n';
                dst += 1;
            }
            start = i + 1;
        }
    }
    return dst;
}

pub fn outdentLines(text: []const u8, spaces: u8, out: []u8) ?usize {
    var dst: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            var line = text[start..i];
            var removed: u8 = 0;
            if (line.len > 0 and line[0] == '\t') {
                line = line[1..];
            } else {
                while (removed < spaces and line.len > 0 and line[0] == ' ') : (removed += 1) {
                    line = line[1..];
                }
            }
            if (dst + line.len > out.len) return null;
            @memcpy(out[dst..][0..line.len], line);
            dst += line.len;
            if (i < text.len) {
                if (dst + 1 > out.len) return null;
                out[dst] = '\n';
                dst += 1;
            }
            start = i + 1;
        }
    }
    return dst;
}

test "toggle comments add and remove" {
    var out: [256]u8 = undefined;
    const n1 = toggleLineComments("foo\nbar\n", "a.ts", &out).?;
    try std.testing.expectEqualStrings("// foo\n// bar\n", out[0..n1]);
    const n2 = toggleLineComments(out[0..n1], "a.ts", &out).?;
    try std.testing.expectEqualStrings("foo\nbar\n", out[0..n2]);
}

test "indent and outdent" {
    var out: [128]u8 = undefined;
    const n1 = indentLines("a\nb\n", 2, &out).?;
    try std.testing.expectEqualStrings("  a\n  b\n", out[0..n1]);
    const n2 = outdentLines(out[0..n1], 2, &out).?;
    try std.testing.expectEqualStrings("a\nb\n", out[0..n2]);
}

pub fn toUpperCase(text: []const u8, out: []u8) ?usize {
    if (text.len > out.len) return null;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        out[i] = std.ascii.toUpper(text[i]);
    }
    return text.len;
}

pub fn toLowerCase(text: []const u8, out: []u8) ?usize {
    if (text.len > out.len) return null;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        out[i] = std.ascii.toLower(text[i]);
    }
    return text.len;
}

/// Lexicographic sort of lines (stable enough for MVP; trailing newline preserved if present).
pub fn sortLines(text: []const u8, out: []u8) ?usize {
    const max_lines = 512;
    var starts: [max_lines]usize = undefined;
    var lens: [max_lines]usize = undefined;
    var count: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    const has_trailing_nl = text.len > 0 and text[text.len - 1] == '\n';
    while (i <= text.len and count < max_lines) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            // Skip the final empty segment after trailing newline
            if (i == text.len and has_trailing_nl and start == text.len) break;
            starts[count] = start;
            lens[count] = i - start;
            count += 1;
            start = i + 1;
            if (i == text.len) break;
        }
    }
    // Simple insertion sort by line content
    var a: usize = 1;
    while (a < count) : (a += 1) {
        var b = a;
        while (b > 0) {
            const left = text[starts[b - 1] ..][0..lens[b - 1]];
            const right = text[starts[b] ..][0..lens[b]];
            if (std.mem.order(u8, left, right) != .gt) break;
            const ts = starts[b - 1];
            const tl = lens[b - 1];
            starts[b - 1] = starts[b];
            lens[b - 1] = lens[b];
            starts[b] = ts;
            lens[b] = tl;
            b -= 1;
        }
    }
    var dst: usize = 0;
    var li: usize = 0;
    while (li < count) : (li += 1) {
        const line = text[starts[li] ..][0..lens[li]];
        if (dst + line.len > out.len) return null;
        @memcpy(out[dst..][0..line.len], line);
        dst += line.len;
        if (li + 1 < count or has_trailing_nl) {
            if (dst + 1 > out.len) return null;
            out[dst] = '\n';
            dst += 1;
        }
    }
    return dst;
}

pub fn reverseLines(text: []const u8, out: []u8) ?usize {
    const max_lines = 512;
    var starts: [max_lines]usize = undefined;
    var lens: [max_lines]usize = undefined;
    var count: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    const has_trailing_nl = text.len > 0 and text[text.len - 1] == '\n';
    while (i <= text.len and count < max_lines) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            if (i == text.len and has_trailing_nl and start == text.len) break;
            starts[count] = start;
            lens[count] = i - start;
            count += 1;
            start = i + 1;
            if (i == text.len) break;
        }
    }
    var dst: usize = 0;
    var li: usize = count;
    while (li > 0) {
        li -= 1;
        const line = text[starts[li] ..][0..lens[li]];
        if (dst + line.len > out.len) return null;
        @memcpy(out[dst..][0..line.len], line);
        dst += line.len;
        if (li > 0 or has_trailing_nl) {
            if (dst + 1 > out.len) return null;
            out[dst] = '\n';
            dst += 1;
        }
    }
    return dst;
}

pub fn trimTrailingWhitespace(text: []const u8, out: []u8) ?usize {
    var dst: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            var end = i;
            while (end > start and (text[end - 1] == ' ' or text[end - 1] == '\t' or text[end - 1] == '\r')) {
                end -= 1;
            }
            const line = text[start..end];
            if (dst + line.len > out.len) return null;
            @memcpy(out[dst..][0..line.len], line);
            dst += line.len;
            if (i < text.len) {
                if (dst + 1 > out.len) return null;
                out[dst] = '\n';
                dst += 1;
            }
            start = i + 1;
        }
    }
    return dst;
}

pub fn ensureFinalNewline(text: []const u8, out: []u8) ?usize {
    if (text.len == 0) {
        if (out.len == 0) return null;
        out[0] = '\n';
        return 1;
    }
    if (text[text.len - 1] == '\n') {
        if (text.len > out.len) return null;
        @memcpy(out[0..text.len], text);
        return text.len;
    }
    if (text.len + 1 > out.len) return null;
    @memcpy(out[0..text.len], text);
    out[text.len] = '\n';
    return text.len + 1;
}

test "case and sort transforms" {
    var out: [128]u8 = undefined;
    const u = toUpperCase("AbC", &out).?;
    try std.testing.expectEqualStrings("ABC", out[0..u]);
    const l = toLowerCase("AbC", &out).?;
    try std.testing.expectEqualStrings("abc", out[0..l]);
    const s = sortLines("c\na\nb\n", &out).?;
    try std.testing.expectEqualStrings("a\nb\nc\n", out[0..s]);
    const r = reverseLines("a\nb\nc\n", &out).?;
    try std.testing.expectEqualStrings("c\nb\na\n", out[0..r]);
}

test "trim trailing and final newline" {
    var out: [64]u8 = undefined;
    const t = trimTrailingWhitespace("a  \nb\t\n", &out).?;
    try std.testing.expectEqualStrings("a\nb\n", out[0..t]);
    const n = ensureFinalNewline("hi", &out).?;
    try std.testing.expectEqualStrings("hi\n", out[0..n]);
}
