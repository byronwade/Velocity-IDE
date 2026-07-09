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

/// Title Case: uppercase first letter of each whitespace-separated word.
pub fn toTitleCase(text: []const u8, out: []u8) ?usize {
    if (text.len > out.len) return null;
    var cap_next = true;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            out[i] = c;
            cap_next = true;
        } else if (cap_next) {
            out[i] = std.ascii.toUpper(c);
            cap_next = false;
        } else {
            out[i] = std.ascii.toLower(c);
        }
    }
    return text.len;
}

/// Collapse runs of blank lines to a single blank line.
pub fn collapseBlankLines(text: []const u8, out: []u8) ?usize {
    var dst: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    var blank_run: u32 = 0;
    const has_trailing_nl = text.len > 0 and text[text.len - 1] == '\n';
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            if (i == text.len and has_trailing_nl and start == text.len) break;
            const line = text[start..i];
            const is_blank = std.mem.trim(u8, line, " \t\r").len == 0;
            if (is_blank) {
                blank_run += 1;
                if (blank_run == 1) {
                    if (dst > 0) {
                        if (dst + 1 > out.len) return null;
                        out[dst] = '\n';
                        dst += 1;
                    }
                }
            } else {
                if (dst > 0) {
                    if (dst + 1 > out.len) return null;
                    out[dst] = '\n';
                    dst += 1;
                }
                if (dst + line.len > out.len) return null;
                @memcpy(out[dst..][0..line.len], line);
                dst += line.len;
                blank_run = 0;
            }
            start = i + 1;
            if (i == text.len) break;
        }
    }
    if (has_trailing_nl and dst > 0 and (dst == 0 or out[dst - 1] != '\n')) {
        if (dst + 1 > out.len) return null;
        out[dst] = '\n';
        dst += 1;
    } else if (has_trailing_nl and blank_run > 0 and dst > 0 and out[dst - 1] != '\n') {
        if (dst + 1 > out.len) return null;
        out[dst] = '\n';
        dst += 1;
    }
    return dst;
}

/// Strip leading and trailing blank lines (keep internal blanks).
pub fn trimBlankLines(text: []const u8, out: []u8) ?usize {
    if (text.len == 0) return 0;
    var start: usize = 0;
    var end = text.len;
    // Leading
    while (start < end) {
        var line_end = start;
        while (line_end < end and text[line_end] != '\n') line_end += 1;
        const line = text[start..line_end];
        if (std.mem.trim(u8, line, " \t\r").len > 0) break;
        start = if (line_end < end) line_end + 1 else end;
    }
    // Trailing
    while (end > start) {
        var line_start = end;
        // If ends with newline, step before it for the last line body.
        if (end > start and text[end - 1] == '\n') {
            line_start = end - 1;
            while (line_start > start and text[line_start - 1] != '\n') line_start -= 1;
            const line = text[line_start .. end - 1];
            if (std.mem.trim(u8, line, " \t\r").len > 0) break;
            end = line_start;
        } else {
            while (line_start > start and text[line_start - 1] != '\n') line_start -= 1;
            const line = text[line_start..end];
            if (std.mem.trim(u8, line, " \t\r").len > 0) break;
            end = line_start;
        }
    }
    const slice = text[start..end];
    if (slice.len > out.len) return null;
    @memcpy(out[0..slice.len], slice);
    return slice.len;
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

fn lastLineRange(text: []const u8) struct { start: usize, end: usize, has_nl: bool } {
    if (text.len == 0) return .{ .start = 0, .end = 0, .has_nl = false };
    var end = text.len;
    var has_nl = false;
    if (text[end - 1] == '\n') {
        has_nl = true;
        end -= 1;
    }
    var start = end;
    while (start > 0 and text[start - 1] != '\n') start -= 1;
    return .{ .start = start, .end = end, .has_nl = has_nl };
}

/// Delete the last line (MVP stand-in for delete line without a caret API).
pub fn deleteLastLine(text: []const u8, out: []u8) ?usize {
    if (text.len == 0) return 0;
    const range = lastLineRange(text);
    const keep = range.start;
    // Drop the newline before the last line when present.
    var cut = keep;
    if (cut > 0 and text[cut - 1] == '\n') cut -= 1;
    if (cut > out.len) return null;
    @memcpy(out[0..cut], text[0..cut]);
    return cut;
}

/// Join all lines with a single space (collapses newlines).
pub fn joinLines(text: []const u8, out: []u8) ?usize {
    var dst: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    var first = true;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            const raw = text[start..i];
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len > 0) {
                if (!first) {
                    if (dst + 1 > out.len) return null;
                    out[dst] = ' ';
                    dst += 1;
                }
                if (dst + line.len > out.len) return null;
                @memcpy(out[dst..][0..line.len], line);
                dst += line.len;
                first = false;
            }
            start = i + 1;
        }
    }
    return dst;
}

/// Swap the last two lines (MVP stand-in for move line up).
pub fn moveLastLineUp(text: []const u8, out: []u8) ?usize {
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
    if (count < 2) {
        if (text.len > out.len) return null;
        @memcpy(out[0..text.len], text);
        return text.len;
    }
    const a = count - 2;
    const b = count - 1;
    const tmp_s = starts[a];
    const tmp_l = lens[a];
    starts[a] = starts[b];
    lens[a] = lens[b];
    starts[b] = tmp_s;
    lens[b] = tmp_l;
    var dst: usize = 0;
    var li: usize = 0;
    while (li < count) : (li += 1) {
        const line = text[starts[li]..][0..lens[li]];
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

/// Rotate last line to the front of the last-two pair (MVP move line down = swap again).
pub fn moveLastLineDown(text: []const u8, out: []u8) ?usize {
    // With only last-line awareness, down == up (swap last two).
    return moveLastLineUp(text, out);
}

pub fn detectEol(text: []const u8) []const u8 {
    if (std.mem.indexOf(u8, text, "\r\n") != null) return "CRLF";
    if (std.mem.indexOfScalar(u8, text, '\n') != null) return "LF";
    return "LF";
}

/// Remove blank / whitespace-only lines.
pub fn removeBlankLines(text: []const u8, out: []u8) ?usize {
    var dst: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    var wrote_any = false;
    const has_trailing_nl = text.len > 0 and text[text.len - 1] == '\n';
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            if (i == text.len and has_trailing_nl and start == text.len) break;
            const line = text[start..i];
            if (std.mem.trim(u8, line, " \t\r").len > 0) {
                if (wrote_any) {
                    if (dst + 1 > out.len) return null;
                    out[dst] = '\n';
                    dst += 1;
                }
                if (dst + line.len > out.len) return null;
                @memcpy(out[dst..][0..line.len], line);
                dst += line.len;
                wrote_any = true;
            }
            start = i + 1;
            if (i == text.len) break;
        }
    }
    if (wrote_any and has_trailing_nl) {
        if (dst + 1 > out.len) return null;
        out[dst] = '\n';
        dst += 1;
    }
    return dst;
}

pub fn insertBlankLineAtEnd(text: []const u8, out: []u8) ?usize {
    if (text.len + 1 > out.len) return null;
    @memcpy(out[0..text.len], text);
    if (text.len == 0 or text[text.len - 1] != '\n') {
        if (text.len + 2 > out.len) return null;
        out[text.len] = '\n';
        out[text.len + 1] = '\n';
        return text.len + 2;
    }
    out[text.len] = '\n';
    return text.len + 1;
}

pub fn countWords(text: []const u8) u32 {
    var words: u32 = 0;
    var in_word = false;
    for (text) |c| {
        const is_ws = c == ' ' or c == '\t' or c == '\n' or c == '\r';
        if (is_ws) {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            words += 1;
        }
    }
    return words;
}

/// Basename of a path (last segment).
pub fn fileNameOf(path: []const u8) []const u8 {
    if (path.len == 0) return path;
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') return path[i + 1 ..];
    }
    return path;
}

pub fn tabsToSpaces(text: []const u8, tab_width: u8, out: []u8) ?usize {
    var dst: usize = 0;
    var col: u8 = 0;
    for (text) |c| {
        if (c == '\t') {
            const spaces = tab_width - (col % tab_width);
            var s: u8 = 0;
            while (s < spaces) : (s += 1) {
                if (dst + 1 > out.len) return null;
                out[dst] = ' ';
                dst += 1;
                col += 1;
            }
        } else {
            if (dst + 1 > out.len) return null;
            out[dst] = c;
            dst += 1;
            if (c == '\n') col = 0 else col +%= 1;
        }
    }
    return dst;
}

pub fn spacesToTabs(text: []const u8, tab_width: u8, out: []u8) ?usize {
    if (tab_width == 0) return null;
    var dst: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            const line = text[start..i];
            var j: usize = 0;
            while (j + tab_width <= line.len) {
                var all_space = true;
                var k: u8 = 0;
                while (k < tab_width) : (k += 1) {
                    if (line[j + k] != ' ') {
                        all_space = false;
                        break;
                    }
                }
                if (!all_space) break;
                if (dst + 1 > out.len) return null;
                out[dst] = '\t';
                dst += 1;
                j += tab_width;
            }
            const rest = line[j..];
            if (dst + rest.len > out.len) return null;
            @memcpy(out[dst..][0..rest.len], rest);
            dst += rest.len;
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

/// Sort lines and drop exact duplicates (preserves first occurrence order after sort).
pub fn sortUniqueLines(text: []const u8, out: []u8) ?usize {
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
    var wrote: usize = 0;
    while (li < count) : (li += 1) {
        const line = text[starts[li] ..][0..lens[li]];
        if (wrote > 0) {
            const prev = text[starts[li - 1] ..][0..lens[li - 1]];
            if (std.mem.eql(u8, prev, line)) continue;
        }
        if (wrote > 0) {
            if (dst + 1 > out.len) return null;
            out[dst] = '\n';
            dst += 1;
        }
        if (dst + line.len > out.len) return null;
        @memcpy(out[dst..][0..line.len], line);
        dst += line.len;
        wrote += 1;
    }
    if (wrote > 0 and has_trailing_nl) {
        if (dst + 1 > out.len) return null;
        out[dst] = '\n';
        dst += 1;
    }
    return dst;
}

pub fn encodingLabel(text: []const u8) []const u8 {
    for (text) |c| {
        if (c >= 0x80) return "UTF-8";
    }
    return "ASCII";
}

pub fn crlfToLf(text: []const u8, out: []u8) ?usize {
    var dst: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\r' and i + 1 < text.len and text[i + 1] == '\n') {
            if (dst + 1 > out.len) return null;
            out[dst] = '\n';
            dst += 1;
            i += 1;
        } else {
            if (dst + 1 > out.len) return null;
            out[dst] = text[i];
            dst += 1;
        }
    }
    return dst;
}

pub fn lfToCrlf(text: []const u8, out: []u8) ?usize {
    var dst: usize = 0;
    for (text) |c| {
        if (c == '\n') {
            if (dst + 2 > out.len) return null;
            out[dst] = '\r';
            out[dst + 1] = '\n';
            dst += 2;
        } else if (c == '\r') {
            // Drop lone CR; paired CRLF handled by skipping when we see LF after.
            continue;
        } else {
            if (dst + 1 > out.len) return null;
            out[dst] = c;
            dst += 1;
        }
    }
    return dst;
}

/// Suggest `name_copy.ext` for a relative path.
pub fn duplicatePathName(path: []const u8, out: []u8) ?usize {
    if (path.len == 0 or path.len + 5 > out.len) return null;
    var slash: usize = 0;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/' or path[i] == '\\') slash = i + 1;
    }
    const dir = path[0..slash];
    const base = path[slash..];
    var dot: ?usize = null;
    var j: usize = 0;
    while (j < base.len) : (j += 1) {
        if (base[j] == '.') dot = j;
    }
    var dst: usize = 0;
    @memcpy(out[dst..][0..dir.len], dir);
    dst += dir.len;
    if (dot) |d| {
        const stem = base[0..d];
        const ext = base[d..];
        if (dst + stem.len + 5 + ext.len > out.len) return null;
        @memcpy(out[dst..][0..stem.len], stem);
        dst += stem.len;
        @memcpy(out[dst..][0..5], "_copy");
        dst += 5;
        @memcpy(out[dst..][0..ext.len], ext);
        dst += ext.len;
    } else {
        if (dst + base.len + 5 > out.len) return null;
        @memcpy(out[dst..][0..base.len], base);
        dst += base.len;
        @memcpy(out[dst..][0..5], "_copy");
        dst += 5;
    }
    return dst;
}

/// Append an ISO-ish UTC timestamp (seconds since epoch formatted).
pub fn formatTimestamp(epoch_secs: i64, out: []u8) ?usize {
    if (out.len < 20) return null;
    // Simple YYYY-MM-DD HH:MM:SS UTC from unix seconds (no leap seconds).
    const secs: u64 = if (epoch_secs < 0) 0 else @intCast(epoch_secs);
    const day_secs: u64 = 86400;
    const days = secs / day_secs;
    const sod = secs % day_secs;
    const hour: u64 = sod / 3600;
    const minute: u64 = (sod % 3600) / 60;
    const second: u64 = sod % 60;
    // Civil from days since 1970-01-01 (Howard Hinnant algorithm).
    const z = days + 719468;
    const era = z / 146097;
    const doe = z - era * 146097;
    const yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const y = yoe + era * 400;
    const doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp = (5 * doy + 2) / 153;
    const d = doy - (153 * mp + 2) / 5 + 1;
    const m = if (mp < 10) mp + 3 else mp - 9;
    const year = if (m <= 2) y + 1 else y;
    const written = std.fmt.bufPrint(out, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{ year, m, d, hour, minute, second }) catch return null;
    return written.len;
}

/// Format a deterministic UUID-like string from a seed (not crypto-random).
pub fn formatUuid(seed: u64, out: []u8) ?usize {
    if (out.len < 36) return null;
    // xorshift-ish mix for stable hex digits from seed.
    var x = seed ^ 0x9e3779b97f4a7c15;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    var bytes: [16]u8 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        x = x *% 0x5851f42d4c957f2d +% 1;
        bytes[i] = @truncate(x >> 32);
    }
    // Version 4 / variant bits for familiar shape.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = "0123456789abcdef";
    var dst: usize = 0;
    const positions = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    for (positions, 0..) |_, bi| {
        if (bi == 4 or bi == 6 or bi == 8 or bi == 10) {
            out[dst] = '-';
            dst += 1;
        }
        out[dst] = hex[bytes[bi] >> 4];
        out[dst + 1] = hex[bytes[bi] & 0xf];
        dst += 2;
    }
    return dst;
}

/// Compare two buffers; returns a short status into `out` (toast-sized).
pub fn compareBuffers(current: []const u8, saved: []const u8, out: []u8) ?usize {
    if (std.mem.eql(u8, current, saved)) {
        const msg = "Matches disk";
        if (out.len < msg.len) return null;
        @memcpy(out[0..msg.len], msg);
        return msg.len;
    }
    var cur_lines: u32 = if (current.len == 0) 0 else 1;
    for (current) |c| {
        if (c == '\n') cur_lines += 1;
    }
    if (current.len == 0) cur_lines = 0;
    var saved_lines: u32 = if (saved.len == 0) 0 else 1;
    for (saved) |c| {
        if (c == '\n') saved_lines += 1;
    }
    if (saved.len == 0) saved_lines = 0;
    const written = std.fmt.bufPrint(out, "Differs: {d}B/{d}L vs disk {d}B/{d}L", .{ current.len, cur_lines, saved.len, saved_lines }) catch return null;
    return written.len;
}

test "case and sort transforms" {
    var out: [128]u8 = undefined;
    const u = toUpperCase("AbC", &out).?;
    try std.testing.expectEqualStrings("ABC", out[0..u]);
    const l = toLowerCase("AbC", &out).?;
    try std.testing.expectEqualStrings("abc", out[0..l]);
    const t = toTitleCase("hello WORLD\nfoo", &out).?;
    try std.testing.expectEqualStrings("Hello World\nFoo", out[0..t]);
    const s = sortLines("c\na\nb\n", &out).?;
    try std.testing.expectEqualStrings("a\nb\nc\n", out[0..s]);
    const r = reverseLines("a\nb\nc\n", &out).?;
    try std.testing.expectEqualStrings("c\nb\na\n", out[0..r]);
    const c = collapseBlankLines("a\n\n\nb\n", &out).?;
    try std.testing.expectEqualStrings("a\n\nb\n", out[0..c]);
    const tb = trimBlankLines("\n\na\nb\n\n", &out).?;
    try std.testing.expectEqualStrings("a\nb\n", out[0..tb]);
}

test "trim trailing and final newline" {
    var out: [64]u8 = undefined;
    const t = trimTrailingWhitespace("a  \nb\t\n", &out).?;
    try std.testing.expectEqualStrings("a\nb\n", out[0..t]);
    const n = ensureFinalNewline("hi", &out).?;
    try std.testing.expectEqualStrings("hi\n", out[0..n]);
}

test "delete join and move last line" {
    var out: [128]u8 = undefined;
    const d = deleteLastLine("a\nb\nc\n", &out).?;
    try std.testing.expectEqualStrings("a\nb", out[0..d]);
    const j = joinLines("a\nb\nc", &out).?;
    try std.testing.expectEqualStrings("a b c", out[0..j]);
    const m = moveLastLineUp("a\nb\nc\n", &out).?;
    try std.testing.expectEqualStrings("a\nc\nb\n", out[0..m]);
    try std.testing.expectEqualStrings("CRLF", detectEol("a\r\nb\n"));
    try std.testing.expectEqualStrings("LF", detectEol("a\nb"));
}

test "blank lines insert remove and words" {
    var out: [128]u8 = undefined;
    const r = removeBlankLines("a\n\nb\n  \nc\n", &out).?;
    try std.testing.expectEqualStrings("a\nb\nc\n", out[0..r]);
    const i = insertBlankLineAtEnd("hi", &out).?;
    try std.testing.expectEqualStrings("hi\n\n", out[0..i]);
    try std.testing.expectEqual(@as(u32, 3), countWords("one two  three"));
    try std.testing.expectEqualStrings("Chart.tsx", fileNameOf("src/components/Chart.tsx"));
}

test "tabs spaces unique sort encoding" {
    var out: [128]u8 = undefined;
    const s = tabsToSpaces("a\tb", 4, &out).?;
    try std.testing.expectEqualStrings("a   b", out[0..s]);
    const t = spacesToTabs("    a\n  b", 4, &out).?;
    try std.testing.expectEqualStrings("\ta\n  b", out[0..t]);
    const u = sortUniqueLines("b\na\nb\nc\n", &out).?;
    try std.testing.expectEqualStrings("a\nb\nc\n", out[0..u]);
    try std.testing.expectEqualStrings("ASCII", encodingLabel("hi"));
}

test "eol convert and duplicate path" {
    var out: [128]u8 = undefined;
    const a = crlfToLf("a\r\nb\r\n", &out).?;
    try std.testing.expectEqualStrings("a\nb\n", out[0..a]);
    const b = lfToCrlf("a\nb\n", &out).?;
    try std.testing.expectEqualStrings("a\r\nb\r\n", out[0..b]);
    const p = duplicatePathName("src/app.tsx", &out).?;
    try std.testing.expectEqualStrings("src/app_copy.tsx", out[0..p]);
    const ts = formatTimestamp(0, &out).?;
    try std.testing.expectEqualStrings("1970-01-01 00:00:00", out[0..ts]);
    const id = formatUuid(1, &out).?;
    try std.testing.expect(id == 36);
    try std.testing.expect(out[8] == '-' and out[13] == '-' and out[18] == '-' and out[23] == '-');
    var cmp: [64]u8 = undefined;
    const same = compareBuffers("hi", "hi", &cmp).?;
    try std.testing.expectEqualStrings("Matches disk", cmp[0..same]);
    const diff = compareBuffers("a\nb", "x", &cmp).?;
    try std.testing.expect(std.mem.indexOf(u8, cmp[0..diff], "Differs") != null);
}
