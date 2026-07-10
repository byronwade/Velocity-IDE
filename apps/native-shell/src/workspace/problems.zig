//! Lightweight "problems" scan — TODO/FIXME/HACK/XXX markers in workspace files.
//! Not a real linter; gives developers a familiar Problems panel without LSP.

const std = @import("std");
const scanner = @import("scanner.zig");
const workspace_store = @import("workspace_store.zig");
const problem_matchers = @import("problem_matchers.zig");

pub const max_problems: usize = 64;
pub const max_preview: usize = 100;

pub const Severity = enum { @"error", warning, info };
pub const Source = enum { marker, terminal, lsp };
pub const SeverityFilter = enum { all, errors, warnings };
pub const SourceFilter = enum { all, terminal, marker, lsp };

/// One diagnostic handed over from the LSP client (already bounded and
/// borrowed from the transport's extraction page).
pub const LspDiagnostic = struct {
    line: u32 = 0,
    column: u32 = 0,
    severity: Severity = .@"error",
    message: []const u8 = "",
};

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
    filtered_items: [max_problems]Problem = [_]Problem{.{}} ** max_problems,
    filtered_count: u32 = 0,
    severity_filter: SeverityFilter = .all,
    source_filter: SourceFilter = .all,
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

    pub fn filteredSlice(self: *ProblemBuffers) []const Problem {
        return self.filtered_items[0..self.filtered_count];
    }

    pub fn setFilters(self: *ProblemBuffers, severity: SeverityFilter, source: SourceFilter) void {
        self.severity_filter = severity;
        self.source_filter = source;
        self.applyFilters();
    }

    pub fn applyFilters(self: *ProblemBuffers) void {
        self.filtered_count = 0;
        for (self.itemsSlice()) |item| {
            const severity_match = switch (self.severity_filter) {
                .all => true,
                .errors => std.mem.eql(u8, item.severity_label, "error"),
                .warnings => std.mem.eql(u8, item.severity_label, "warning"),
            };
            const source_match = switch (self.source_filter) {
                .all => true,
                .terminal => std.mem.eql(u8, item.source_label, "terminal"),
                .marker => std.mem.eql(u8, item.source_label, "marker"),
                .lsp => std.mem.eql(u8, item.source_label, "lsp"),
            };
            if (!severity_match or !source_match) continue;
            self.filtered_items[self.filtered_count] = item;
            self.filtered_count += 1;
        }
    }

    pub fn clear(self: *ProblemBuffers) void {
        self.item_count = 0;
        self.filtered_count = 0;
        self.error_count = 0;
        self.warning_count = 0;
        self.status = "idle";
    }

    pub fn scan(self: *ProblemBuffers, io: std.Io, ws: *workspace_store.WorkspaceBuffers) void {
        self.removeWhere(.marker, null);
        self.status = "scanning";
        const terminal_count = self.item_count;
        var file_buf: [scanner.max_file_bytes]u8 = undefined;
        var i: u32 = 0;
        while (i < ws.file_node_count and self.item_count < max_problems) : (i += 1) {
            const node = ws.file_nodes[i];
            if (node.is_dir) continue;
            const n = scanner.readTextFile(io, ws.rootPath(), node.path, file_buf[0..]) catch continue;
            self.scanFile(node.path, file_buf[0..n]);
        }
        const marker_count = self.item_count - terminal_count;
        if (marker_count == 0 and terminal_count == 0) {
            self.status = "no markers";
        } else if (terminal_count == 0) {
            self.status = std.fmt.bufPrint(&self.status_buf, "{d} markers", .{marker_count}) catch "done";
        } else {
            self.status = std.fmt.bufPrint(
                &self.status_buf,
                "{d} markers · {d} terminal",
                .{ marker_count, terminal_count },
            ) catch "done";
        }
        self.applyFilters();
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
        self.removeWhere(.terminal, null);
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
        self.applyFilters();
    }

    /// Replace the bounded LSP diagnostics for one file (publishDiagnostics
    /// semantics: each publish supersedes the previous set for its URI).
    /// Other sources and other files' LSP rows are untouched. Diagnostics
    /// beyond the remaining capacity are dropped, never split.
    pub fn replaceLspForPath(self: *ProblemBuffers, path: []const u8, diagnostics: []const LspDiagnostic) void {
        self.removeWhere(.lsp, path);
        for (diagnostics) |diagnostic| {
            if (self.item_count >= max_problems) break;
            self.push(
                path,
                diagnostic.line,
                diagnostic.column,
                severityLabel(diagnostic.severity),
                diagnostic.message,
                diagnostic.severity,
                .lsp,
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
        self.applyFilters();
    }

    /// Compact away items of `source` (optionally only those for `path`),
    /// preserving every other source so marker/terminal/lsp rows coexist.
    fn removeWhere(self: *ProblemBuffers, source: Source, path: ?[]const u8) void {
        var retained: u32 = 0;
        var errors: u32 = 0;
        var warnings: u32 = 0;
        const dropped = sourceLabel(source);
        var index: u32 = 0;
        while (index < self.item_count) : (index += 1) {
            const item = self.items[index];
            const source_matches = std.mem.eql(u8, item.source_label, dropped);
            const path_matches = if (path) |p| std.mem.eql(u8, item.path, p) else true;
            if (source_matches and path_matches) continue;
            const path_bytes = item.path;
            const kind = item.kind;
            const preview = item.preview;
            const plen = @min(path_bytes.len, self.path_pool[retained].len);
            const klen = @min(kind.len, self.kind_pool[retained].len);
            const vlen = @min(preview.len, self.preview_pool[retained].len);
            std.mem.copyForwards(u8, self.path_pool[retained][0..plen], path_bytes[0..plen]);
            std.mem.copyForwards(u8, self.kind_pool[retained][0..klen], kind[0..klen]);
            std.mem.copyForwards(u8, self.preview_pool[retained][0..vlen], preview[0..vlen]);
            self.items[retained] = .{
                .id = retained + 1,
                .path = self.path_pool[retained][0..plen],
                .line = item.line,
                .column = item.column,
                .kind = self.kind_pool[retained][0..klen],
                .preview = self.preview_pool[retained][0..vlen],
                .severity_label = item.severity_label,
                .source_label = item.source_label,
            };
            if (std.mem.eql(u8, item.severity_label, "error")) errors += 1;
            if (std.mem.eql(u8, item.severity_label, "warning")) warnings += 1;
            retained += 1;
        }
        self.item_count = retained;
        self.error_count = errors;
        self.warning_count = warnings;
        self.filtered_count = 0;
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
        .lsp => "lsp",
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

test "problems expose filtered iterable and counts" {
    var p: ProblemBuffers = .{};
    p.scanFile("src/a.ts", "// TODO warning\n");
    p.applyFilters();
    try std.testing.expectEqual(@as(u32, 1), p.filtered_count);
    p.setFilters(.errors, .all);
    try std.testing.expectEqual(@as(u32, 0), p.filtered_count);
    p.setFilters(.warnings, .marker);
    try std.testing.expectEqual(@as(u32, 1), p.filtered_count);
    try std.testing.expectEqualStrings("marker", p.filteredSlice()[0].source_label);
}

test "lsp diagnostics replace per path and coexist with other sources" {
    var p: ProblemBuffers = .{};
    p.scanFile("src/a.ts", "// TODO warning\n");
    p.applyFilters();

    const first = [_]LspDiagnostic{
        .{ .line = 3, .column = 5, .severity = .@"error", .message = "Type 'string' is not assignable" },
        .{ .line = 9, .column = 1, .severity = .warning, .message = "unused variable" },
    };
    p.replaceLspForPath("src/a.ts", &first);
    try std.testing.expectEqual(@as(u32, 3), p.item_count);
    try std.testing.expectEqual(@as(u32, 1), p.error_count);

    // A later publish for the same URI replaces its rows (LSP semantics)…
    const second = [_]LspDiagnostic{
        .{ .line = 4, .column = 2, .severity = .@"error", .message = "still broken" },
    };
    p.replaceLspForPath("src/a.ts", &second);
    try std.testing.expectEqual(@as(u32, 2), p.item_count);

    // …without touching other files' LSP rows or other sources.
    p.replaceLspForPath("src/b.ts", &first);
    try std.testing.expectEqual(@as(u32, 4), p.item_count);
    p.replaceLspForPath("src/a.ts", &.{});
    try std.testing.expectEqual(@as(u32, 3), p.item_count);
    p.setFilters(.all, .lsp);
    try std.testing.expectEqual(@as(u32, 2), p.filtered_count);
    try std.testing.expectEqualStrings("lsp", p.filteredSlice()[0].source_label);
    try std.testing.expectEqualStrings("src/b.ts", p.filteredSlice()[0].path);
    p.setFilters(.all, .marker);
    try std.testing.expectEqual(@as(u32, 1), p.filtered_count);
}

test "lsp diagnostics are truncated at the problems cap, never split" {
    var p: ProblemBuffers = .{};
    var flood: [max_problems + 10]LspDiagnostic = undefined;
    for (&flood, 0..) |*d, i| {
        d.* = .{ .line = @intCast(i + 1), .column = 1, .severity = .@"error", .message = "boom" };
    }
    p.replaceLspForPath("src/huge.ts", &flood);
    try std.testing.expectEqual(@as(u32, @intCast(max_problems)), p.item_count);
    // Re-publishing replaces rather than accumulating.
    p.replaceLspForPath("src/huge.ts", flood[0..2]);
    try std.testing.expectEqual(@as(u32, 2), p.item_count);
}

test "marker rescans and terminal ingests preserve lsp rows" {
    var p: ProblemBuffers = .{};
    const lsp_rows = [_]LspDiagnostic{
        .{ .line = 1, .column = 1, .severity = .@"error", .message = "lsp says no" },
    };
    p.replaceLspForPath("src/a.ts", &lsp_rows);
    p.scanFile("src/a.ts", "// TODO marker\n");
    p.applyFilters();
    var matched: problem_matchers.MatcherBuffers = .{};
    const lines = [_][]const u8{"src/a.ts(2,1): error TS1: broken"};
    matched.parseLines(&lines);
    p.ingestDiagnostics(matched.diagnosticsSlice());
    try std.testing.expectEqual(@as(u32, 3), p.item_count);
    p.setFilters(.all, .lsp);
    try std.testing.expectEqual(@as(u32, 1), p.filtered_count);
    try std.testing.expectEqualStrings("lsp says no", p.filteredSlice()[0].preview);
}

test "marker and terminal sources coexist and refresh independently" {
    var p: ProblemBuffers = .{};
    p.scanFile("src/a.ts", "// TODO warning\n");
    p.applyFilters();
    var matched: problem_matchers.MatcherBuffers = .{};
    const lines = [_][]const u8{"src/a.ts(2,1): error TS1: broken"};
    matched.parseLines(&lines);
    p.ingestDiagnostics(matched.diagnosticsSlice());
    try std.testing.expectEqual(@as(u32, 2), p.item_count);
    p.setFilters(.all, .marker);
    try std.testing.expectEqual(@as(u32, 1), p.filtered_count);
    p.setFilters(.all, .terminal);
    try std.testing.expectEqual(@as(u32, 1), p.filtered_count);
}
