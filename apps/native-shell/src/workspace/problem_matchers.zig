//! Bounded terminal problem matchers — compiler/test output to diagnostics.
//! Supports TypeScript, Zig, GCC/Clang, generic path:line, and test stacks.

const std = @import("std");
const scanner = @import("scanner.zig");

pub const max_diagnostics: usize = 64;
pub const max_message: usize = 120;
pub const max_code: usize = 20;

pub const Severity = enum { @"error", warning, info };

pub const Diagnostic = struct {
    id: u32 = 0,
    path: []const u8 = "",
    line: u32 = 0,
    column: u32 = 0,
    severity: Severity = .info,
    code: []const u8 = "",
    message: []const u8 = "",
};

pub const MatcherBuffers = struct {
    diagnostics: [max_diagnostics]Diagnostic = [_]Diagnostic{.{}} ** max_diagnostics,
    path_pool: [max_diagnostics][scanner.max_rel_path_len]u8 = undefined,
    message_pool: [max_diagnostics][max_message]u8 = undefined,
    code_pool: [max_diagnostics][max_code]u8 = undefined,
    count: u32 = 0,
    error_count: u32 = 0,
    warning_count: u32 = 0,
    status: []const u8 = "idle",
    status_buf: [64]u8 = undefined,

    pub fn diagnosticsSlice(self: *const MatcherBuffers) []const Diagnostic {
        return self.diagnostics[0..self.count];
    }

    pub fn clear(self: *MatcherBuffers) void {
        self.count = 0;
        self.error_count = 0;
        self.warning_count = 0;
        self.status = "idle";
    }

    pub fn parseLines(self: *MatcherBuffers, lines: []const []const u8) void {
        self.clear();
        for (lines) |raw| {
            if (self.count >= max_diagnostics) break;
            var clean_buf: [512]u8 = undefined;
            const clean = stripAnsi(raw, &clean_buf);
            if (parseLine(clean)) |hit| self.push(hit);
        }
        self.status = if (self.count == 0)
            "no diagnostics"
        else
            std.fmt.bufPrint(
                &self.status_buf,
                "{d} errors · {d} warnings · {d} total",
                .{ self.error_count, self.warning_count, self.count },
            ) catch "diagnostics";
    }

    fn push(self: *MatcherBuffers, hit: Parsed) void {
        if (self.count >= max_diagnostics) return;
        for (self.diagnosticsSlice()) |existing| {
            if (existing.line == hit.line and
                std.mem.eql(u8, existing.path, hit.path) and
                std.mem.eql(u8, existing.message, hit.message))
            {
                return;
            }
        }
        const idx = self.count;
        const plen = @min(hit.path.len, self.path_pool[idx].len);
        @memcpy(self.path_pool[idx][0..plen], hit.path[0..plen]);
        const mlen = @min(hit.message.len, self.message_pool[idx].len);
        @memcpy(self.message_pool[idx][0..mlen], hit.message[0..mlen]);
        const clen = @min(hit.code.len, self.code_pool[idx].len);
        @memcpy(self.code_pool[idx][0..clen], hit.code[0..clen]);
        self.diagnostics[idx] = .{
            .id = idx + 1,
            .path = self.path_pool[idx][0..plen],
            .line = hit.line,
            .column = hit.column,
            .severity = hit.severity,
            .code = self.code_pool[idx][0..clen],
            .message = self.message_pool[idx][0..mlen],
        };
        switch (hit.severity) {
            .@"error" => self.error_count += 1,
            .warning => self.warning_count += 1,
            .info => {},
        }
        self.count += 1;
    }
};

const Parsed = struct {
    path: []const u8,
    line: u32,
    column: u32,
    severity: Severity,
    code: []const u8,
    message: []const u8,
};

fn parseLine(line_raw: []const u8) ?Parsed {
    const line = std.mem.trim(u8, line_raw, " \t\r");
    if (line.len == 0) return null;
    // Command echo is context, not compiler output.
    if (std.mem.startsWith(u8, line, "$ ")) return null;
    // npm prints lifecycle metadata and the script command with a `> ` prefix.
    if (std.mem.startsWith(u8, line, "> ")) return null;
    if (parseTestStackLocation(line)) |hit| return hit;
    if (parseParenLocation(line)) |hit| return hit;
    return parseColonLocation(line);
}

fn parseTestStackLocation(line: []const u8) ?Parsed {
    var location = line;
    if (std.mem.startsWith(u8, location, "❯ ")) {
        location = std.mem.trim(u8, location["❯ ".len..], " \t");
    } else if (std.mem.startsWith(u8, location, "at ")) {
        const open = std.mem.lastIndexOfScalar(u8, location, '(');
        if (open) |index| {
            if (!std.mem.endsWith(u8, location, ")")) return null;
            location = location[index + 1 .. location.len - 1];
        } else {
            location = std.mem.trim(u8, location["at ".len..], " \t");
        }
        // Framework internals are stack context, not user-facing Problems.
        if (std.mem.indexOf(u8, location, ".test.") == null and
            std.mem.indexOf(u8, location, ".spec.") == null)
        {
            return null;
        }
    } else {
        return null;
    }
    const parsed = parseBareLocation(location) orelse return null;
    return .{
        .path = parsed.path,
        .line = parsed.line,
        .column = parsed.column,
        .severity = .@"error",
        .code = "TEST",
        .message = "Test assertion failed",
    };
}

fn parseBareLocation(location_raw: []const u8) ?Parsed {
    const location = normalizePath(location_raw);
    const last = std.mem.lastIndexOfScalar(u8, location, ':') orelse return null;
    const column = parsePositive(location[last + 1 ..]) orelse return null;
    const before_column = location[0..last];
    const previous = std.mem.lastIndexOfScalar(u8, before_column, ':') orelse return null;
    const line = parsePositive(before_column[previous + 1 ..]) orelse return null;
    const path = normalizePath(before_column[0..previous]);
    if (!validPath(path)) return null;
    return .{
        .path = path,
        .line = line,
        .column = column,
        .severity = .@"error",
        .code = "TEST",
        .message = "Test assertion failed",
    };
}

fn parseParenLocation(line: []const u8) ?Parsed {
    const open = std.mem.indexOfScalar(u8, line, '(') orelse return null;
    const close_rel = std.mem.indexOfScalar(u8, line[open + 1 ..], ')') orelse return null;
    const close = open + 1 + close_rel;
    const location = line[open + 1 .. close];
    const comma = std.mem.indexOfScalar(u8, location, ',') orelse return null;
    const line_no = parsePositive(location[0..comma]) orelse return null;
    const column = parsePositive(location[comma + 1 ..]) orelse return null;
    const path = normalizePath(line[0..open]);
    if (!validPath(path)) return null;
    const rest = std.mem.trimStart(u8, line[close + 1 ..], " \t:");
    return finishParsed(path, line_no, column, rest);
}

fn parseColonLocation(line: []const u8) ?Parsed {
    var colon: usize = 0;
    while (colon < line.len) : (colon += 1) {
        if (line[colon] != ':') continue;
        const after = line[colon + 1 ..];
        const line_end = digitPrefixLen(after);
        if (line_end == 0 or colon == 0) continue;
        const line_no = parsePositive(after[0..line_end]) orelse continue;
        var cursor = colon + 1 + line_end;
        var column: u32 = 0;
        if (cursor < line.len and line[cursor] == ':') {
            const col_start = cursor + 1;
            const col_len = digitPrefixLen(line[col_start..]);
            if (col_len > 0) {
                column = parsePositive(line[col_start .. col_start + col_len]) orelse 0;
                cursor = col_start + col_len;
            }
        }
        if (cursor >= line.len or line[cursor] != ':') continue;
        const path = normalizePath(line[0..colon]);
        if (!validPath(path)) continue;
        const rest = std.mem.trimStart(u8, line[cursor + 1 ..], " \t:");
        return finishParsed(path, line_no, column, rest);
    }
    return null;
}

fn finishParsed(path: []const u8, line: u32, column: u32, rest_raw: []const u8) Parsed {
    var rest = std.mem.trim(u8, rest_raw, " \t\r");
    var severity: Severity = .info;
    if (consumePrefixIgnoreCase(rest, "error")) |next| {
        severity = .@"error";
        rest = next;
    } else if (consumePrefixIgnoreCase(rest, "warning")) |next| {
        severity = .warning;
        rest = next;
    } else if (consumePrefixIgnoreCase(rest, "note")) |next| {
        rest = next;
    } else if (consumePrefixIgnoreCase(rest, "info")) |next| {
        rest = next;
    }
    rest = std.mem.trimStart(u8, rest, " \t:");
    var code: []const u8 = "";
    if (rest.len > 2 and (std.ascii.startsWithIgnoreCase(rest, "TS") or std.ascii.startsWithIgnoreCase(rest, "E"))) {
        const end = tokenEnd(rest);
        code = rest[0..end];
        rest = std.mem.trimStart(u8, rest[end..], " \t:");
    }
    return .{
        .path = path,
        .line = line,
        .column = column,
        .severity = severity,
        .code = code,
        .message = if (rest.len > 0) rest else "Problem",
    };
}

fn consumePrefixIgnoreCase(text: []const u8, prefix: []const u8) ?[]const u8 {
    if (text.len < prefix.len or !std.ascii.eqlIgnoreCase(text[0..prefix.len], prefix)) return null;
    if (text.len > prefix.len and std.ascii.isAlphabetic(text[prefix.len])) return null;
    return text[prefix.len..];
}

fn normalizePath(path_raw: []const u8) []const u8 {
    var path = std.mem.trim(u8, path_raw, " \t\"'");
    while (std.mem.startsWith(u8, path, "./")) path = path[2..];
    return path;
}

fn validPath(path: []const u8) bool {
    return path.len > 0 and
        path.len <= scanner.max_rel_path_len and
        std.mem.indexOfScalar(u8, path, '\n') == null and
        (std.mem.indexOfScalar(u8, path, '/') != null or
            std.mem.indexOfScalar(u8, path, '\\') != null or
            std.mem.indexOfScalar(u8, path, '.') != null);
}

fn parsePositive(text: []const u8) ?u32 {
    if (text.len == 0) return null;
    var value: u32 = 0;
    for (text) |c| {
        if (!std.ascii.isDigit(c)) return null;
        value = std.math.mul(u32, value, 10) catch return null;
        value = std.math.add(u32, value, c - '0') catch return null;
    }
    return if (value == 0) null else value;
}

fn digitPrefixLen(text: []const u8) usize {
    var count: usize = 0;
    while (count < text.len and std.ascii.isDigit(text[count])) : (count += 1) {}
    return count;
}

fn tokenEnd(text: []const u8) usize {
    var i: usize = 0;
    while (i < text.len and !std.ascii.isWhitespace(text[i]) and text[i] != ':') : (i += 1) {}
    return i;
}

fn stripAnsi(input: []const u8, out: []u8) []const u8 {
    var src: usize = 0;
    var dst: usize = 0;
    while (src < input.len and dst < out.len) {
        if (input[src] == 0x1b and src + 1 < input.len and input[src + 1] == '[') {
            src += 2;
            while (src < input.len) : (src += 1) {
                const c = input[src];
                if (c >= '@' and c <= '~') {
                    src += 1;
                    break;
                }
            }
            continue;
        }
        out[dst] = input[src];
        dst += 1;
        src += 1;
    }
    return out[0..dst];
}

test "parses TypeScript diagnostic" {
    var buffers: MatcherBuffers = .{};
    const lines = [_][]const u8{"src/app.tsx(12,5): error TS2345: Bad argument"};
    buffers.parseLines(&lines);
    try std.testing.expectEqual(@as(u32, 1), buffers.count);
    try std.testing.expectEqualStrings("src/app.tsx", buffers.diagnostics[0].path);
    try std.testing.expectEqual(@as(u32, 12), buffers.diagnostics[0].line);
    try std.testing.expectEqual(@as(u32, 5), buffers.diagnostics[0].column);
    try std.testing.expect(buffers.diagnostics[0].severity == .@"error");
    try std.testing.expectEqualStrings("TS2345", buffers.diagnostics[0].code);
}

test "parses Zig and GCC style diagnostics with ANSI" {
    var buffers: MatcherBuffers = .{};
    const lines = [_][]const u8{
        "\x1b[31msrc/main.zig:42:13: error: expected ';'\x1b[0m",
        "src/foo.c:9:2: warning: unused value",
    };
    buffers.parseLines(&lines);
    try std.testing.expectEqual(@as(u32, 2), buffers.count);
    try std.testing.expectEqual(@as(u32, 1), buffers.error_count);
    try std.testing.expectEqual(@as(u32, 1), buffers.warning_count);
}

test "ignores noise and deduplicates diagnostics" {
    var buffers: MatcherBuffers = .{};
    const lines = [_][]const u8{
        "building project...",
        "src/main.zig:4:2: error: broken",
        "src/main.zig:4:2: error: broken",
    };
    buffers.parseLines(&lines);
    try std.testing.expectEqual(@as(u32, 1), buffers.count);
}

test "parses Vitest and Jest assertion locations but ignores framework stacks" {
    var buffers: MatcherBuffers = .{};
    const lines = [_][]const u8{
        " ❯ tests/app.test.ts:12:7",
        "    at Object.<anonymous> (tests/app.test.ts:12:7)",
        "    at runTest (node_modules/vitest/runner.js:55:2)",
        "    at helper (src/helper.ts:4:1)",
    };
    buffers.parseLines(&lines);
    try std.testing.expectEqual(@as(u32, 1), buffers.count);
    try std.testing.expectEqualStrings("tests/app.test.ts", buffers.diagnostics[0].path);
    try std.testing.expectEqualStrings("TEST", buffers.diagnostics[0].code);
    try std.testing.expectEqual(@as(u32, 12), buffers.diagnostics[0].line);
    try std.testing.expectEqual(@as(u32, 7), buffers.diagnostics[0].column);
    try std.testing.expect(buffers.diagnostics[0].severity == .@"error");
}
