//! Document outline — heuristic symbol extraction (no LSP).
//! Scans for common function/class/heading patterns across languages.

const std = @import("std");

pub const max_symbols: usize = 64;
pub const max_name_len: usize = 80;
pub const max_kind_len: usize = 16;

pub const Symbol = struct {
    id: u32 = 0,
    name: []const u8 = "",
    kind: []const u8 = "",
    line: u32 = 0,
};

pub const OutlineBuffers = struct {
    symbols: [max_symbols]Symbol = [_]Symbol{.{}} ** max_symbols,
    name_pool: [max_symbols][max_name_len]u8 = undefined,
    kind_pool: [max_symbols][max_kind_len]u8 = undefined,
    name_lens: [max_symbols]usize = [_]usize{0} ** max_symbols,
    kind_lens: [max_symbols]usize = [_]usize{0} ** max_symbols,
    count: u32 = 0,
    status: []const u8 = "idle",

    pub fn symbolsSlice(self: *const OutlineBuffers) []const Symbol {
        return self.symbols[0..self.count];
    }

    pub fn clear(self: *OutlineBuffers) void {
        self.count = 0;
        self.status = "idle";
    }

    pub fn scan(self: *OutlineBuffers, text: []const u8, path: []const u8) void {
        self.clear();
        var line_no: u32 = 1;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= text.len) : (i += 1) {
            if (i == text.len or text[i] == '\n') {
                const raw = text[start..i];
                const line = std.mem.trim(u8, raw, " \t\r");
                if (line.len > 0) {
                    if (matchSymbol(line, path)) |hit| {
                        self.push(hit.name, hit.kind, line_no);
                    }
                }
                line_no += 1;
                start = i + 1;
                if (self.count >= max_symbols) break;
            }
        }
        self.status = if (self.count == 0) "no symbols" else "done";
    }

    fn push(self: *OutlineBuffers, name: []const u8, kind: []const u8, line: u32) void {
        if (self.count >= max_symbols) return;
        const idx = self.count;
        const nlen = @min(name.len, self.name_pool[idx].len);
        @memcpy(self.name_pool[idx][0..nlen], name[0..nlen]);
        self.name_lens[idx] = nlen;
        const klen = @min(kind.len, self.kind_pool[idx].len);
        @memcpy(self.kind_pool[idx][0..klen], kind[0..klen]);
        self.kind_lens[idx] = klen;
        self.symbols[idx] = .{
            .id = idx + 1,
            .name = self.name_pool[idx][0..nlen],
            .kind = self.kind_pool[idx][0..klen],
            .line = line,
        };
        self.count += 1;
    }
};

const Hit = struct { name: []const u8, kind: []const u8 };

fn matchSymbol(line: []const u8, path: []const u8) ?Hit {
    if (std.mem.endsWith(u8, path, ".md") or std.mem.endsWith(u8, path, ".markdown")) {
        if (std.mem.startsWith(u8, line, "# ")) return .{ .name = line[2..], .kind = "h1" };
        if (std.mem.startsWith(u8, line, "## ")) return .{ .name = line[3..], .kind = "h2" };
        if (std.mem.startsWith(u8, line, "### ")) return .{ .name = line[4..], .kind = "h3" };
    }
    if (takeAfter(line, "export function ")) |n| return .{ .name = stripName(n), .kind = "fn" };
    if (takeAfter(line, "export default function ")) |n| return .{ .name = stripName(n), .kind = "fn" };
    if (takeAfter(line, "export class ")) |n| return .{ .name = stripName(n), .kind = "class" };
    if (takeAfter(line, "function ")) |n| return .{ .name = stripName(n), .kind = "fn" };
    if (takeAfter(line, "class ")) |n| return .{ .name = stripName(n), .kind = "class" };
    if (takeAfter(line, "pub fn ")) |n| return .{ .name = stripName(n), .kind = "fn" };
    if (takeAfter(line, "fn ")) |n| return .{ .name = stripName(n), .kind = "fn" };
    if (takeAfter(line, "pub struct ")) |n| return .{ .name = stripName(n), .kind = "struct" };
    if (takeAfter(line, "struct ")) |n| return .{ .name = stripName(n), .kind = "struct" };
    if (takeAfter(line, "def ")) |n| return .{ .name = stripName(n), .kind = "fn" };
    if (takeAfter(line, "async def ")) |n| return .{ .name = stripName(n), .kind = "fn" };
    if (takeAfter(line, "const ")) |rest| {
        if (std.mem.indexOf(u8, rest, " = ") != null or std.mem.indexOf(u8, rest, "=>") != null) {
            return .{ .name = stripName(rest), .kind = "const" };
        }
    }
    return null;
}

fn takeAfter(line: []const u8, prefix: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, line, prefix)) return line[prefix.len..];
    // Allow indented
    const trimmed = std.mem.trimStart(u8, line, " \t");
    if (std.mem.startsWith(u8, trimmed, prefix)) return trimmed[prefix.len..];
    return null;
}

fn stripName(raw: []const u8) []const u8 {
    var end: usize = 0;
    while (end < raw.len) : (end += 1) {
        const c = raw[end];
        if (c == '(' or c == '{' or c == ':' or c == ' ' or c == '<' or c == '=' or c == '\t') break;
    }
    if (end == 0) return raw;
    return raw[0..end];
}

test "outline finds ts function" {
    var bufs: OutlineBuffers = .{};
    bufs.scan(
        \\import x from "y";
        \\
        \\export function Chart() {
        \\  return null;
        \\}
        \\
        \\export class App {}
    ,
        "app.tsx",
    );
    try std.testing.expect(bufs.count >= 2);
    try std.testing.expectEqualStrings("Chart", bufs.symbols[0].name);
    try std.testing.expectEqual(@as(u32, 3), bufs.symbols[0].line);
}
