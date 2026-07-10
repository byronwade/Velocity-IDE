//! Copyright (c) Velocity IDE contributors.
//! Bounded unified line diff construction and read-only review projection.

const std = @import("std");

pub const max_source_lines: usize = 256;
pub const max_review_lines: usize = 320;
pub const max_line_bytes: usize = 512;
pub const max_raw_bytes: usize = 32 * 1024;

pub const LineKind = enum { metadata, context, addition, deletion };

pub const ReviewLine = struct {
    id: u32 = 0,
    marker: []const u8 = "",
    text: []const u8 = "",
    kind: LineKind = .context,
    kind_label: []const u8 = "context",
};

pub const Review = struct {
    lines: [max_review_lines]ReviewLine = [_]ReviewLine{.{}} ** max_review_lines,
    line_count: u32 = 0,
    line_pool: [max_review_lines][max_line_bytes]u8 = undefined,
    line_lens: [max_review_lines]usize = [_]usize{0} ** max_review_lines,
    title_buf: [256]u8 = undefined,
    title: []const u8 = "Diff Review",
    status_buf: [128]u8 = undefined,
    status: []const u8 = "No diff",
    truncated: bool = false,

    pub fn slice(self: *const Review) []const ReviewLine {
        return self.lines[0..self.line_count];
    }

    pub fn clear(self: *Review) void {
        self.line_count = 0;
        self.truncated = false;
        self.title = "Diff Review";
        self.status = "No diff";
    }

    pub fn build(self: *Review, saved: []const u8, working: []const u8, path: []const u8) void {
        self.clear();
        self.setTitle("Diff Review — {s}", .{path});

        var saved_lines: [max_source_lines][]const u8 = undefined;
        var working_lines: [max_source_lines][]const u8 = undefined;
        const saved_result = splitLines(saved, &saved_lines);
        const working_result = splitLines(working, &working_lines);
        self.truncated = saved_result.truncated or working_result.truncated;
        const old = saved_lines[0..saved_result.count];
        const new = working_lines[0..working_result.count];

        self.push(.metadata, "---", path);
        self.push(.metadata, "+++", path);
        var hunk: [80]u8 = undefined;
        const hunk_text = std.fmt.bufPrint(&hunk, "-1,{d} +1,{d} @@", .{ old.len, new.len }) catch "-1 +1 @@";
        self.push(.metadata, "@@", hunk_text);

        var matrix: [max_source_lines + 1][max_source_lines + 1]u16 = [_][max_source_lines + 1]u16{
            [_]u16{0} ** (max_source_lines + 1),
        } ** (max_source_lines + 1);
        var old_index = old.len;
        while (old_index > 0) {
            old_index -= 1;
            var new_index = new.len;
            while (new_index > 0) {
                new_index -= 1;
                matrix[old_index][new_index] = if (std.mem.eql(u8, old[old_index], new[new_index]))
                    matrix[old_index + 1][new_index + 1] + 1
                else
                    @max(matrix[old_index + 1][new_index], matrix[old_index][new_index + 1]);
            }
        }

        old_index = 0;
        var new_index: usize = 0;
        while (old_index < old.len or new_index < new.len) {
            if (old_index < old.len and new_index < new.len and std.mem.eql(u8, old[old_index], new[new_index])) {
                self.push(.context, " ", old[old_index]);
                old_index += 1;
                new_index += 1;
            } else if (new_index < new.len and (old_index == old.len or matrix[old_index][new_index + 1] >= matrix[old_index + 1][new_index])) {
                self.push(.addition, "+", new[new_index]);
                new_index += 1;
            } else {
                self.push(.deletion, "-", old[old_index]);
                old_index += 1;
            }
            if (self.line_count >= max_review_lines) {
                self.truncated = true;
                break;
            }
        }
        self.finishStatus();
    }

    /// Projects already-unified Git output into bounded, classified review lines.
    pub fn parseUnified(self: *Review, raw: []const u8, title_text: []const u8, mode_label: []const u8, input_truncated: bool) void {
        self.clear();
        self.setTitle("Diff Review — {s}", .{title_text});
        self.truncated = input_truncated or raw.len > max_raw_bytes;
        const bounded = raw[0..@min(raw.len, max_raw_bytes)];
        var start: usize = 0;
        var index: usize = 0;
        while (index <= bounded.len) : (index += 1) {
            if (index != bounded.len and bounded[index] != '\n') continue;
            var line = bounded[start..index];
            if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
            const kind: LineKind = if (std.mem.startsWith(u8, line, "+++") or std.mem.startsWith(u8, line, "---") or
                std.mem.startsWith(u8, line, "@@") or std.mem.startsWith(u8, line, "diff ") or
                std.mem.startsWith(u8, line, "index "))
                .metadata
            else if (std.mem.startsWith(u8, line, "+"))
                .addition
            else if (std.mem.startsWith(u8, line, "-"))
                .deletion
            else
                .context;
            const marker: []const u8 = switch (kind) {
                .addition => "+",
                .deletion => "-",
                .context => " ",
                .metadata => "·",
            };
            const text = if ((kind == .addition or kind == .deletion) and line.len > 0) line[1..] else line;
            self.push(kind, marker, text);
            if (self.line_count >= max_review_lines) {
                self.truncated = true;
                break;
            }
            start = index + 1;
        }
        const written = std.fmt.bufPrint(&self.status_buf, "{s} · {d} lines{s}", .{
            mode_label,
            self.line_count,
            if (self.truncated) " · truncated" else "",
        }) catch "Diff review";
        self.status = written;
    }

    pub fn copyText(self: *const Review, out: []u8) []const u8 {
        var used: usize = 0;
        for (self.slice()) |line| {
            const metadata_passthrough = line.kind == .metadata and std.mem.eql(u8, line.marker, "·");
            const separator_len: usize = if (line.kind == .metadata and !metadata_passthrough) 1 else 0;
            const marker_len: usize = if (metadata_passthrough) 0 else line.marker.len;
            const needed = marker_len + separator_len + line.text.len + 1;
            if (needed > out.len - used) break;
            if (!metadata_passthrough) {
                @memcpy(out[used..][0..line.marker.len], line.marker);
                used += line.marker.len;
            }
            if (separator_len == 1) {
                out[used] = ' ';
                used += 1;
            }
            @memcpy(out[used..][0..line.text.len], line.text);
            used += line.text.len;
            out[used] = '\n';
            used += 1;
        }
        return out[0..used];
    }

    fn push(self: *Review, kind: LineKind, marker: []const u8, text: []const u8) void {
        if (self.line_count >= max_review_lines) {
            self.truncated = true;
            return;
        }
        const index = self.line_count;
        const length = @min(text.len, max_line_bytes);
        @memcpy(self.line_pool[index][0..length], text[0..length]);
        self.line_lens[index] = length;
        if (length < text.len) self.truncated = true;
        self.lines[index] = .{
            .id = index + 1,
            .marker = marker,
            .text = self.line_pool[index][0..length],
            .kind = kind,
            .kind_label = @tagName(kind),
        };
        self.line_count += 1;
    }

    fn setTitle(self: *Review, comptime format: []const u8, args: anytype) void {
        self.title = std.fmt.bufPrint(&self.title_buf, format, args) catch "Diff Review";
    }

    fn finishStatus(self: *Review) void {
        const written = std.fmt.bufPrint(&self.status_buf, "{d} lines{s}", .{
            self.line_count,
            if (self.truncated) " · truncated" else "",
        }) catch "Diff review";
        self.status = written;
    }
};

const SplitResult = struct {
    count: usize,
    truncated: bool,
};

fn splitLines(text: []const u8, out: [][]const u8) SplitResult {
    var count: usize = 0;
    var start: usize = 0;
    var index: usize = 0;
    while (index <= text.len) : (index += 1) {
        if (index != text.len and text[index] != '\n') continue;
        if (count >= out.len) return .{ .count = count, .truncated = true };
        var line = text[start..index];
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        out[count] = line;
        count += 1;
        start = index + 1;
    }
    return .{ .count = count, .truncated = false };
}

test "bounded line diff classifies additions deletions and context" {
    var review: Review = .{};
    review.build("one\ntwo\nthree\n", "one\nchanged\nthree\n", "file.txt");
    var additions: usize = 0;
    var deletions: usize = 0;
    var context: usize = 0;
    for (review.slice()) |line| switch (line.kind) {
        .addition => additions += 1,
        .deletion => deletions += 1,
        .context => context += 1,
        .metadata => {},
    };
    try std.testing.expectEqual(@as(usize, 1), additions);
    try std.testing.expectEqual(@as(usize, 1), deletions);
    try std.testing.expect(context >= 2);
    try std.testing.expect(!review.truncated);
    var copied: [4096]u8 = undefined;
    const text = review.copyText(&copied);
    try std.testing.expect(std.mem.startsWith(u8, text, "--- file.txt\n+++ file.txt\n@@ "));
}

test "unified parser marks oversized input truncated" {
    var review: Review = .{};
    var raw: [max_raw_bytes + 1]u8 = [_]u8{'x'} ** (max_raw_bytes + 1);
    raw[0] = '+';
    review.parseUnified(&raw, "file.txt", "unstaged", false);
    try std.testing.expect(review.truncated);
    try std.testing.expect(review.slice()[0].kind == .addition);
}
