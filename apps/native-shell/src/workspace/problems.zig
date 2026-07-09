//! Lightweight "problems" scan — TODO/FIXME/HACK/XXX markers in workspace files.
//! Not a real linter; gives developers a familiar Problems panel without LSP.

const std = @import("std");
const scanner = @import("scanner.zig");
const workspace_store = @import("workspace_store.zig");
const problem_matchers = @import("problem_matchers.zig");

pub const max_problems: usize = 64;
pub const max_preview: usize = 100;

pub const Severity = enum { @"error", warning, info };
pub const Source = enum { marker, terminal };

pub const Problem = struct {
    id: u32 = 0,
    path: []const u8 = "",
    line: u32 = 0,
    column: u32 = 0,
    kind: []const u8 = "",
    preview: []const u8 = "",
    severity_label: []const u8 = "info",
    source_label: []const u8 = "marker",
};

pub const ProblemBuffers = struct {
    items: [max_problems]Problem = [_]Problem{.{}} ** max_problems,
    item_count: u32 = 0,
    path_pool: [max_problems][scanner.max_rel_path_len]u8 = undefined,
    path_lens: [max_problems]usize = [_]usize{0} ** max_problems,
    preview_pool: [max_problems][max_preview]u8 = undefined,
    preview_lens: [max_problems]usize = [_]usize{0} ** max_problems,
    kind_pool: [max_problems][8]u8 = undefined,
    kind_lens: [max_problems]usize = [_]usize{0} ** max_problems,
    error_count: u32 = 0,
    warning_count: u32 = 0,
    status: []const u8 = "idle",
    status_buf: [64]u8 = undefined,

    pub fn itemsSlice(self: *ProblemBuffers) []const Problem {
        return self.items[0..self.item_count];
    }

    pub fn clear(self: *ProblemBuffers) void {
        self.item_count = 0;
        self.error_count = 0;
        self.warning_count = 0;
        self.status = "idle";
    }

    pub fn scan(self: *ProblemBuffers, io: std.Io, ws: *workspace_store.WorkspaceBuffers) void {
        self.clear();
        self.status = "scanning";
        var file_buf: [scanner.max_file_bytes]u8 = undefined;
        var i: u32 = 0;
        while (i < ws.file_node_count and self.item_count < max_problems) : (i += 1) {
            const node = ws.file_nodes[i];
            if (node.is_dir) continue;
            const n = scanner.readTextFile(io, ws.rootPath(), node.path, file_buf[0..]) catch continue;
            self.scanFile(node.path, file_buf[0..n]);
        }
        if (self.item_count == 0) {
            self.status = "no markers";
        } else {
            self.status = std.fmt.bufPrint(&self.status_buf, "{d} markers", .{self.item_count}) catch "done";
        }
    }

    pub fn scanFile(self: *ProblemBuffers, path: []const u8, content: []const u8) void {
        var line_no: u32 = 1;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= content.len and self.item_count < max_problems) : (i += 1) {
            if (i == content.len or content[i] == '\n') {
                const line = content[start..i];
                if (markerInLine(line)) |kind| {
                    self.push(path, line_no, 0, kind, line, .warning, .marker);
                }
                line_no += 1;
                start = i + 1;
            }
        }
    }

    pub fn ingestDiagnostics(
        self: *ProblemBuffers,
        diagnostics: []const problem_matchers.Diagnostic,
    ) void {
        self.clear();
        for (diagnostics) |diagnostic| {
            if (self.item_count >= max_problems) break;
            const severity: Severity = switch (diagnostic.severity) {
                .@"error" => .@"error",
                .warning => .warning,
                .info => .info,
            };
            const kind = if (diagnostic.code.len > 0)
                diagnostic.code
            else
                severityLabel(severity);
            self.push(
                diagnostic.path,
                diagnostic.line,
                diagnostic.column,
                kind,
                diagnostic.message,
                severity,
                .terminal,
            );
        }
        self.status = if (self.item_count == 0)
            "no diagnostics"
        else
            std.fmt.bufPrint(
                &self.status_buf,
                "{d} errors · {d} warnings · {d} total",
                .{ self.error_count, self.warning_count, self.item_count },
            ) catch "diagnostics";
    }

    fn markerInLine(line: []const u8) ?[]const u8 {
        const markers = [_][]const u8{ "TODO", "FIXME", "HACK", "XXX" };
        for (markers) |m| {
            if (std.ascii.indexOfIgnoreCase(line, m) != null) return m;
        }
        return null;
    }

    fn push(
        self: *ProblemBuffers,
        path: []const u8,
        line: u32,
        column: u32,
        kind: []const u8,
        preview_src: []const u8,
        severity: Severity,
        source: Source,
    ) void {
        const idx = self.item_count;
        const plen = @min(path.len, self.path_pool[idx].len);
        @memcpy(self.path_pool[idx][0..plen], path[0..plen]);
        self.path_lens[idx] = plen;
        const klen = @min(kind.len, self.kind_pool[idx].len);
        @memcpy(self.kind_pool[idx][0..klen], kind[0..klen]);
        self.kind_lens[idx] = klen;
        const trimmed = std.mem.trim(u8, preview_src, " \t\r");
        const vlen = @min(trimmed.len, self.preview_pool[idx].len);
        @memcpy(self.preview_pool[idx][0..vlen], trimmed[0..vlen]);
        self.preview_lens[idx] = vlen;
        self.items[idx] = .{
            .id = idx + 1,
            .path = self.path_pool[idx][0..plen],
            .line = line,
            .column = column,
            .kind = self.kind_pool[idx][0..klen],
            .preview = self.preview_pool[idx][0..vlen],
            .severity_label = severityLabel(severity),
            .source_label = sourceLabel(source),
        };
        switch (severity) {
            .@"error" => self.error_count += 1,
            .warning => self.warning_count += 1,
            .info => {},
        }
        self.item_count += 1;
    }
};

fn severityLabel(severity: Severity) []const u8 {
    return switch (severity) {
        .@"error" => "error",
        .warning => "warning",
        .info => "info",
    };
}

fn sourceLabel(source: Source) []const u8 {
    return switch (source) {
        .marker => "marker",
        .terminal => "terminal",
    };
}

test "problems finds TODO marker" {
    var p: ProblemBuffers = .{};
    // Direct scanFile via temporary content through push path
    p.scanFile("src/a.ts", "const x = 1;\n// TODO: wire this\n");
    try std.testing.expect(p.item_count == 1);
    try std.testing.expectEqualStrings("TODO", p.items[0].kind);
    try std.testing.expect(p.items[0].line == 2);
    try std.testing.expectEqualStrings("warning", p.items[0].severity_label);
}

test "problems ingest compiler diagnostics" {
    var matched: problem_matchers.MatcherBuffers = .{};
    const lines = [_][]const u8{"src/a.ts(7,3): error TS1001: Broken"};
    matched.parseLines(&lines);
    var p: ProblemBuffers = .{};
    p.ingestDiagnostics(matched.diagnosticsSlice());
    try std.testing.expectEqual(@as(u32, 1), p.item_count);
    try std.testing.expectEqual(@as(u32, 1), p.error_count);
    try std.testing.expectEqualStrings("terminal", p.items[0].source_label);
    try std.testing.expectEqualStrings("TS1001", p.items[0].kind);
}
