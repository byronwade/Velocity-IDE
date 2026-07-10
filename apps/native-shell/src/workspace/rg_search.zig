//! Governed ripgrep adapter for workspace-wide search.
//!
//! This module is self-contained (argv builder + output parser + availability
//! probe + one-shot runner) and follows the proven `src/scm/git_status.zig`
//! pattern: argv-based single-shot spawns through `std.process.run` with
//! bounded stdout/stderr limits — never a shell string, never streaming state.
//!
//! Output format choice — `--line-number --column --no-heading --null` instead
//! of `--json`:
//!   * `--null` prints `path\x00line:col:text\n`, so the path is NUL-delimited
//!     exactly like `git status --porcelain -z` (already parsed by
//!     `GitBuffers.parsePorcelainZ`). Paths with `:`? Unambiguous. Every other
//!     field is fixed-position digits. No decoder state, trivially bounded.
//!   * `--json` would require a bounded JSON string unescaper (`\n`, `\"`,
//!     `\uXXXX`, plus a base64 `bytes` fallback for non-UTF8 paths) — strictly
//!     more failure surface for no field we need. Rejected.
//! Line length beyond `max_preview` is bounded twice: rg itself truncates via
//! `--max-columns=200 --max-columns-preview` (so one minified line cannot eat
//! the stdout budget), and the parser clamps the preview again, setting the
//! hit's `preview_truncated` flag.
//!
//! === Integration surface (orchestrator / app_model) ===
//! Call sequence for one governed search (single-shot, like git_status):
//!   1. Model state: `rg_probe: rg_search.Probe = .{}` and a heap slot
//!      `rg_results: ?*rg_search.Results = null` (the struct is ~45 KiB —
//!      allocate like `workspace_replace_bufs`, never by value in Model).
//!   2. On the search Msg (recommended: `.run_rg_search`), app_model calls
//!      `rg_search.runSearch(results, &model.rg_probe, io, ws.rootPath(),
//!      query, options)` and stores the returned bounded status string.
//!      Governor bookkeeping mirrors git_status: record the one-shot under
//!      feature "workspace.rg_search" around the call if ledgering is wanted.
//!   3. The probe spawns `rg --version` at most once, only on first search
//!      demand; `.unavailable` is cached and surfaced as the literal status
//!      "ripgrep unavailable" so the UI can fall back to the built-in
//!      `search.zig` scanner. `Probe.reset()` re-arms detection (e.g. after
//!      the user installs rg).
//!   4. UI reads `results.hitsSlice()`, `results.filePath(hit.file_index)`
//!      (hits are grouped: consecutive hits share a file_index because argv
//!      pins `--sort=path`), and the truncation flags
//!      {hits_truncated, files_truncated, output_truncated, malformed_lines}
//!      for honest "results limited" badges.
//! Recommended Msg additions: `.run_rg_search` (and reuse the existing search
//! query/option fields). No timers, no streaming: one spawn, one parse.

const std = @import("std");
const scanner = @import("scanner.zig");

pub const max_hits: usize = 128;
pub const max_files: usize = 64;
pub const max_preview: usize = 200;
pub const max_query: usize = 256;
pub const max_glob: usize = 96;
pub const max_rel_path: usize = scanner.max_rel_path_len;
pub const max_argv: usize = 24;
/// Total child stdout budget for one search. Exceeding it aborts the run
/// (std.process.run reports an error and the partial output is discarded);
/// runSearch then reports "results exceed bounded limit" with
/// `output_truncated` set. rg-side bounds (--max-count, --max-columns) make
/// this a pathological case (thousands of matching files).
pub const max_stdout_bytes: usize = 512 * 1024;

comptime {
    // The argv builder embeds the scanner's per-file ceiling so ripgrep skips
    // exactly the files the built-in scanner would refuse to read.
    std.debug.assert(scanner.max_file_bytes == 256 * 1024);
}

pub const MatchMode = enum { literal, regex };

pub const Options = struct {
    mode: MatchMode = .literal,
    case_sensitive: bool = false,
    whole_word: bool = false,
    /// Single rg glob (e.g. "src/**/*.ts"). Empty = no include filter.
    include_glob: []const u8 = "",
    /// Single rg glob; passed as a negated `--glob=!…`. Empty = no exclude.
    exclude_glob: []const u8 = "",
    /// Global hit budget enforced by the parser; also passed as rg's
    /// per-file `--max-count` (rg has no global cap flag). 0 or anything
    /// above `max_hits` clamps to `max_hits`.
    max_results: u32 = max_hits,
};

pub const BuildError = error{
    EmptyQuery,
    QueryTooLong,
    InvalidQuery,
    GlobTooLong,
    InvalidGlob,
};

/// A fully materialized literal argument array. All argument bytes live in
/// this struct's own buffers, so the caller's query/glob slices may be
/// reused immediately after `buildArgv` returns.
/// IMPORTANT: args point into the struct's buffers — build in place via
/// `buildArgv(&argv, …)` and never copy an Argv by value afterwards.
pub const Argv = struct {
    args: [max_argv][]const u8 = undefined,
    len: usize = 0,
    query_buf: [max_query]u8 = undefined,
    include_buf: ["--glob=".len + max_glob]u8 = undefined,
    exclude_buf: ["--glob=!".len + max_glob]u8 = undefined,
    max_count_buf: [24]u8 = undefined,

    pub fn slice(self: *const Argv) []const []const u8 {
        return self.args[0..self.len];
    }
};

fn containsNulOrNewline(bytes: []const u8) bool {
    for (bytes) |b| {
        if (b == 0 or b == '\n' or b == '\r') return true;
    }
    return false;
}

pub fn clampedMaxResults(requested: u32) u32 {
    if (requested == 0 or requested > max_hits) return @intCast(max_hits);
    return requested;
}

/// Build the exact literal argv for one search. Never a shell string; every
/// value is a distinct argv element passed to execve as-is. `--no-config` is
/// always present; ignore files (.gitignore/.ignore) are respected by rg's
/// defaults on purpose. `./` is passed as an explicit search path so a
/// non-tty stdin can never make rg read stdin instead of the workspace.
pub fn buildArgv(out: *Argv, query: []const u8, options: Options) BuildError!void {
    out.len = 0;
    const trimmed = std.mem.trim(u8, query, " \t");
    if (trimmed.len == 0) return BuildError.EmptyQuery;
    if (trimmed.len > max_query) return BuildError.QueryTooLong;
    if (containsNulOrNewline(trimmed)) return BuildError.InvalidQuery;

    const include = std.mem.trim(u8, options.include_glob, " \t");
    const exclude = std.mem.trim(u8, options.exclude_glob, " \t");
    if (include.len > max_glob or exclude.len > max_glob) return BuildError.GlobTooLong;
    if (containsNulOrNewline(include) or containsNulOrNewline(exclude)) return BuildError.InvalidGlob;

    @memcpy(out.query_buf[0..trimmed.len], trimmed);
    const query_arg = out.query_buf[0..trimmed.len];

    var n: usize = 0;
    const fixed = [_][]const u8{
        "rg",
        "--no-config",
        "--line-number",
        "--column",
        "--no-heading",
        "--null",
        "--color=never",
        std.fmt.comptimePrint("--max-columns={d}", .{max_preview}),
        "--max-columns-preview",
        std.fmt.comptimePrint("--max-filesize={d}", .{scanner.max_file_bytes}),
        "--sort=path",
    };
    for (fixed) |arg| {
        out.args[n] = arg;
        n += 1;
    }
    if (options.mode == .literal) {
        out.args[n] = "--fixed-strings";
        n += 1;
    }
    out.args[n] = if (options.case_sensitive) "--case-sensitive" else "--ignore-case";
    n += 1;
    if (options.whole_word) {
        out.args[n] = "--word-regexp";
        n += 1;
    }
    if (include.len > 0) {
        const prefix = "--glob=";
        @memcpy(out.include_buf[0..prefix.len], prefix);
        @memcpy(out.include_buf[prefix.len..][0..include.len], include);
        out.args[n] = out.include_buf[0 .. prefix.len + include.len];
        n += 1;
    }
    if (exclude.len > 0) {
        const prefix = "--glob=!";
        @memcpy(out.exclude_buf[0..prefix.len], prefix);
        @memcpy(out.exclude_buf[prefix.len..][0..exclude.len], exclude);
        out.args[n] = out.exclude_buf[0 .. prefix.len + exclude.len];
        n += 1;
    }
    out.args[n] = std.fmt.bufPrint(
        &out.max_count_buf,
        "--max-count={d}",
        .{clampedMaxResults(options.max_results)},
    ) catch unreachable;
    n += 1;
    out.args[n] = "-e";
    n += 1;
    out.args[n] = query_arg;
    n += 1;
    out.args[n] = "./";
    n += 1;
    out.len = n;
}

pub const RgHit = struct {
    id: u32 = 0,
    /// Index into Results file table; consecutive hits share an index
    /// (rg output is sorted by path), giving grouping for free.
    file_index: u16 = 0,
    line: u32 = 0,
    column: u32 = 0,
    preview: []const u8 = "",
    preview_truncated: bool = false,
};

/// Bounded parse results. ~45 KiB — heap-allocate one instance in the model
/// (`?*Results`, like `workspace_replace_bufs`); never store by value.
pub const Results = struct {
    file_path_pool: [max_files][max_rel_path]u8 = undefined,
    file_path_lens: [max_files]usize = [_]usize{0} ** max_files,
    file_hit_counts: [max_files]u32 = [_]u32{0} ** max_files,
    file_count: u16 = 0,

    hits: [max_hits]RgHit = [_]RgHit{.{}} ** max_hits,
    hit_count: u32 = 0,
    preview_pool: [max_hits][max_preview]u8 = undefined,
    preview_lens: [max_hits]usize = [_]usize{0} ** max_hits,

    /// More matching lines existed than the enforced hit budget.
    hits_truncated: bool = false,
    /// More distinct files matched than `max_files`; their hits were dropped.
    files_truncated: bool = false,
    /// Child stdout exceeded `max_stdout_bytes` (results discarded upstream)
    /// or the caller flagged a cut stream.
    output_truncated: bool = false,
    /// Lines that were not `path\x00line:col:text` — skipped, never fatal.
    malformed_lines: u32 = 0,

    status: []const u8 = "idle",
    status_buf: [48]u8 = undefined,

    pub fn hitsSlice(self: *const Results) []const RgHit {
        return self.hits[0..self.hit_count];
    }

    pub fn filePath(self: *const Results, index: u16) []const u8 {
        if (index >= self.file_count) return "";
        return self.file_path_pool[index][0..self.file_path_lens[index]];
    }

    pub fn fileHitCount(self: *const Results, index: u16) u32 {
        if (index >= self.file_count) return 0;
        return self.file_hit_counts[index];
    }

    pub fn clear(self: *Results) void {
        self.file_count = 0;
        self.hit_count = 0;
        self.hits_truncated = false;
        self.files_truncated = false;
        self.output_truncated = false;
        self.malformed_lines = 0;
        self.status = "idle";
    }

    /// Parse a complete captured rg stdout buffer (`--null` line format).
    /// `limit` is the global hit budget (0 → max_hits). `stream_truncated`
    /// marks output that was cut mid-stream; a trailing partial line then
    /// parses with a clamped preview or counts as malformed — never a crash.
    pub fn parse(self: *Results, data: []const u8, limit: u32, stream_truncated: bool) void {
        self.clear();
        self.output_truncated = stream_truncated;
        const budget = clampedMaxResults(limit);
        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            if (self.hit_count >= budget) {
                self.hits_truncated = true;
                break;
            }
            self.parseLine(line);
        }
        // Exactly at budget with no residual lines leaves hits_truncated false.
    }

    fn parseLine(self: *Results, line: []const u8) void {
        const nul = std.mem.indexOfScalar(u8, line, 0) orelse {
            self.malformed_lines += 1;
            return;
        };
        var path = line[0..nul];
        if (std.mem.startsWith(u8, path, "./")) path = path[2..];
        if (path.len == 0 or path.len > max_rel_path) {
            self.malformed_lines += 1;
            return;
        }
        const rest = line[nul + 1 ..];
        const first_colon = std.mem.indexOfScalar(u8, rest, ':') orelse {
            self.malformed_lines += 1;
            return;
        };
        const after_line = rest[first_colon + 1 ..];
        const second_colon = std.mem.indexOfScalar(u8, after_line, ':') orelse {
            self.malformed_lines += 1;
            return;
        };
        const line_no = std.fmt.parseInt(u32, rest[0..first_colon], 10) catch {
            self.malformed_lines += 1;
            return;
        };
        const column = std.fmt.parseInt(u32, after_line[0..second_colon], 10) catch {
            self.malformed_lines += 1;
            return;
        };
        if (line_no == 0 or column == 0) {
            self.malformed_lines += 1;
            return;
        }
        const preview_src = after_line[second_colon + 1 ..];

        const file_index = self.internFile(path) orelse return;
        const idx = self.hit_count;
        const trimmed = std.mem.trim(u8, preview_src, " \t\r");
        const vlen = @min(trimmed.len, max_preview);
        @memcpy(self.preview_pool[idx][0..vlen], trimmed[0..vlen]);
        self.preview_lens[idx] = vlen;
        self.hits[idx] = .{
            .id = idx + 1,
            .file_index = file_index,
            .line = line_no,
            .column = column,
            .preview = self.preview_pool[idx][0..vlen],
            .preview_truncated = trimmed.len > max_preview,
        };
        self.hit_count += 1;
        self.file_hit_counts[file_index] += 1;
    }

    fn internFile(self: *Results, path: []const u8) ?u16 {
        if (self.file_count > 0) {
            const last = self.file_count - 1;
            if (std.mem.eql(u8, self.filePath(last), path)) return last;
        }
        if (self.file_count >= max_files) {
            self.files_truncated = true;
            return null;
        }
        const idx = self.file_count;
        @memcpy(self.file_path_pool[idx][0..path.len], path);
        self.file_path_lens[idx] = path.len;
        self.file_hit_counts[idx] = 0;
        self.file_count += 1;
        return idx;
    }
};

pub const Availability = enum { unknown, available, unavailable };

/// Lazy, cached availability probe. Never spawns before first search demand:
/// app_model calls `ensure` only when the user actually runs an rg search.
/// One `rg --version` spawn maximum per state; result is cached until
/// `reset()`. `exe` is overridable only for tests.
pub const Probe = struct {
    exe: []const u8 = "rg",
    state: Availability = .unknown,
    version_buf: [64]u8 = undefined,
    version_len: usize = 0,

    pub fn version(self: *const Probe) []const u8 {
        return self.version_buf[0..self.version_len];
    }

    pub fn reset(self: *Probe) void {
        self.state = .unknown;
        self.version_len = 0;
    }

    pub fn ensure(self: *Probe, io: std.Io) Availability {
        if (self.state != .unknown) return self.state;
        self.state = .unavailable;
        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();
        const result = std.process.run(gpa, io, .{
            .argv = &.{ self.exe, "--version" },
            .stdout_limit = .limited(256),
            .stderr_limit = .limited(256),
        }) catch return self.state;
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        switch (result.term) {
            .exited => |code| if (code != 0) return self.state,
            else => return self.state,
        }
        if (!std.mem.startsWith(u8, result.stdout, "ripgrep")) return self.state;
        const line_end = std.mem.indexOfScalar(u8, result.stdout, '\n') orelse result.stdout.len;
        const first_line = std.mem.trim(u8, result.stdout[0..line_end], " \t\r");
        const n = @min(first_line.len, self.version_buf.len);
        @memcpy(self.version_buf[0..n], first_line[0..n]);
        self.version_len = n;
        self.state = .available;
        return self.state;
    }
};

/// One governed single-shot search (probe → build argv → spawn → parse).
/// Returns a bounded status string (same idiom as GitBuffers), with parsed
/// hits and truncation flags left in `results`.
pub fn runSearch(
    results: *Results,
    probe: *Probe,
    io: std.Io,
    cwd: []const u8,
    query: []const u8,
    options: Options,
) []const u8 {
    results.clear();
    if (cwd.len == 0) {
        results.status = "no workspace";
        return results.status;
    }
    if (probe.ensure(io) != .available) {
        results.status = "ripgrep unavailable";
        return results.status;
    }
    var argv: Argv = .{};
    buildArgv(&argv, query, options) catch |err| {
        results.status = switch (err) {
            BuildError.EmptyQuery => "empty query",
            BuildError.QueryTooLong => "query too long",
            BuildError.InvalidQuery => "invalid query",
            BuildError.GlobTooLong => "glob too long",
            BuildError.InvalidGlob => "invalid glob",
        };
        return results.status;
    };

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    const result = std.process.run(gpa, io, .{
        .argv = argv.slice(),
        .cwd = .{ .path = cwd },
        .stdout_limit = .limited(max_stdout_bytes),
        .stderr_limit = .limited(4096),
    }) catch {
        // Includes stdout exceeding the bounded budget; partial output is
        // intentionally discarded rather than showing a silently-cut list.
        results.output_truncated = true;
        results.status = "results exceed bounded limit";
        return results.status;
    };
    defer {
        gpa.free(result.stdout);
        gpa.free(result.stderr);
    }

    const exit_code: u8 = switch (result.term) {
        .exited => |code| code,
        else => {
            results.status = "search failed";
            return results.status;
        },
    };
    // rg: 0 = matches, 1 = no matches, 2 = error (matches may still have
    // been printed when only some files failed — parse honestly either way).
    if (exit_code == 1) {
        results.status = "no matches";
        return results.status;
    }
    if (exit_code > 2) {
        results.status = "search failed";
        return results.status;
    }
    results.parse(result.stdout, options.max_results, false);
    if (exit_code == 2 and results.hit_count == 0) {
        results.status = "search error";
        return results.status;
    }
    const truncated = results.hits_truncated or results.files_truncated or results.output_truncated;
    if (results.hit_count == 0) {
        results.status = "no matches";
    } else if (truncated) {
        results.status = std.fmt.bufPrint(
            &results.status_buf,
            "{d} hits (truncated)",
            .{results.hit_count},
        ) catch "hits (truncated)";
    } else if (exit_code == 2) {
        results.status = std.fmt.bufPrint(
            &results.status_buf,
            "{d} hits (some files skipped)",
            .{results.hit_count},
        ) catch "hits (some files skipped)";
    } else {
        results.status = std.fmt.bufPrint(
            &results.status_buf,
            "{d} hits",
            .{results.hit_count},
        ) catch "done";
    }
    return results.status;
}

// ---------------------------------------------------------------------------
// Tests — argv correctness
// ---------------------------------------------------------------------------

const base_argv = [_][]const u8{
    "rg",
    "--no-config",
    "--line-number",
    "--column",
    "--no-heading",
    "--null",
    "--color=never",
    "--max-columns=200",
    "--max-columns-preview",
    "--max-filesize=262144",
    "--sort=path",
};

fn expectExactArgv(actual: *const Argv, expected: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, 0..) |want, i| {
        try std.testing.expectEqualStrings(want, actual.args[i]);
    }
}

/// Expected argv for a given option set, built independently of buildArgv.
fn expectedFor(
    buf: *[max_argv][]const u8,
    query: []const u8,
    options: Options,
    glob_include: []const u8,
    glob_exclude: []const u8,
    max_count: []const u8,
) []const []const u8 {
    var n: usize = 0;
    for (base_argv) |arg| {
        buf[n] = arg;
        n += 1;
    }
    if (options.mode == .literal) {
        buf[n] = "--fixed-strings";
        n += 1;
    }
    buf[n] = if (options.case_sensitive) "--case-sensitive" else "--ignore-case";
    n += 1;
    if (options.whole_word) {
        buf[n] = "--word-regexp";
        n += 1;
    }
    if (glob_include.len > 0) {
        buf[n] = glob_include;
        n += 1;
    }
    if (glob_exclude.len > 0) {
        buf[n] = glob_exclude;
        n += 1;
    }
    buf[n] = max_count;
    n += 1;
    buf[n] = "-e";
    n += 1;
    buf[n] = query;
    n += 1;
    buf[n] = "./";
    n += 1;
    return buf[0..n];
}

test "argv defaults: literal, ignore-case, no globs, full budget" {
    var argv: Argv = .{};
    try buildArgv(&argv, "createSession", .{});
    var buf: [max_argv][]const u8 = undefined;
    const expected = expectedFor(&buf, "createSession", .{}, "", "", "--max-count=128");
    try expectExactArgv(&argv, expected);
}

test "argv covers every literal/case/word combination exactly" {
    const modes = [_]MatchMode{ .literal, .regex };
    const bools = [_]bool{ false, true };
    for (modes) |mode| {
        for (bools) |case_sensitive| {
            for (bools) |whole_word| {
                const options: Options = .{
                    .mode = mode,
                    .case_sensitive = case_sensitive,
                    .whole_word = whole_word,
                };
                var argv: Argv = .{};
                try buildArgv(&argv, "needle", options);
                var buf: [max_argv][]const u8 = undefined;
                const expected = expectedFor(&buf, "needle", options, "", "", "--max-count=128");
                try expectExactArgv(&argv, expected);
            }
        }
    }
}

test "argv include and exclude globs become single negatable --glob tokens" {
    var argv: Argv = .{};
    try buildArgv(&argv, "fn main", .{
        .mode = .regex,
        .include_glob = "src/**/*.ts",
        .exclude_glob = "*.test.ts",
        .max_results = 5,
    });
    var buf: [max_argv][]const u8 = undefined;
    const expected = expectedFor(
        &buf,
        "fn main",
        .{ .mode = .regex },
        "--glob=src/**/*.ts",
        "--glob=!*.test.ts",
        "--max-count=5",
    );
    try expectExactArgv(&argv, expected);
}

test "argv trims query and globs, clamps max_results, self-owns bytes" {
    var query_storage: [16]u8 = undefined;
    @memcpy(query_storage[0..9], "  TODO:  ");
    var argv: Argv = .{};
    try buildArgv(&argv, query_storage[0..9], .{
        .include_glob = " *.zig ",
        .max_results = 100_000,
    });
    // Mutate the caller's storage: Argv must not alias it.
    @memset(query_storage[0..9], 'X');
    var buf: [max_argv][]const u8 = undefined;
    const expected = expectedFor(&buf, "TODO:", .{}, "--glob=*.zig", "", "--max-count=128");
    try expectExactArgv(&argv, expected);

    var zero: Argv = .{};
    try buildArgv(&zero, "q", .{ .max_results = 0 });
    try std.testing.expectEqualStrings("--max-count=128", zero.args[zero.len - 4]);
}

test "argv rejects empty, oversized, and unencodable inputs" {
    var argv: Argv = .{};
    try std.testing.expectError(BuildError.EmptyQuery, buildArgv(&argv, "", .{}));
    try std.testing.expectError(BuildError.EmptyQuery, buildArgv(&argv, "  \t ", .{}));
    const long_query = [_]u8{'a'} ** (max_query + 1);
    try std.testing.expectError(BuildError.QueryTooLong, buildArgv(&argv, &long_query, .{}));
    try std.testing.expectError(BuildError.InvalidQuery, buildArgv(&argv, "a\nb", .{}));
    try std.testing.expectError(BuildError.InvalidQuery, buildArgv(&argv, "a\x00b", .{}));
    const long_glob = [_]u8{'g'} ** (max_glob + 1);
    try std.testing.expectError(BuildError.GlobTooLong, buildArgv(&argv, "q", .{ .include_glob = &long_glob }));
    try std.testing.expectError(BuildError.GlobTooLong, buildArgv(&argv, "q", .{ .exclude_glob = &long_glob }));
    try std.testing.expectError(BuildError.InvalidGlob, buildArgv(&argv, "q", .{ .include_glob = "a\nb" }));
}

test "argv worst case still fits max_argv" {
    var argv: Argv = .{};
    try buildArgv(&argv, "q", .{
        .mode = .literal,
        .case_sensitive = true,
        .whole_word = true,
        .include_glob = "*.a",
        .exclude_glob = "*.b",
        .max_results = 7,
    });
    try std.testing.expect(argv.len <= max_argv);
}

// ---------------------------------------------------------------------------
// Tests — parser (fixtures captured from `rg 14.1.0 --null` on
// fixtures/acme-dashboard; format `path\x00line:col:text\n`)
// ---------------------------------------------------------------------------

const captured_fixture =
    "./src/server/auth.ts\x001:17:export function createSession(userId: string) {\n" ++
    "./src/server/auth.ts\x002:6:  // TODO: wire real session store\n" ++
    "./src/app.tsx\x004:23:import { createSession } from \"./server/auth\";\n";

test "parser groups real captured rg output by file with line and column" {
    const results = try std.testing.allocator.create(Results);
    defer std.testing.allocator.destroy(results);
    results.* = .{};
    results.parse(captured_fixture, 0, false);

    try std.testing.expectEqual(@as(u32, 3), results.hit_count);
    try std.testing.expectEqual(@as(u16, 2), results.file_count);
    try std.testing.expectEqualStrings("src/server/auth.ts", results.filePath(0));
    try std.testing.expectEqualStrings("src/app.tsx", results.filePath(1));
    try std.testing.expectEqual(@as(u32, 2), results.fileHitCount(0));
    try std.testing.expectEqual(@as(u32, 1), results.fileHitCount(1));

    const hit = results.hits[0];
    try std.testing.expectEqual(@as(u16, 0), hit.file_index);
    try std.testing.expectEqual(@as(u32, 1), hit.line);
    try std.testing.expectEqual(@as(u32, 17), hit.column);
    try std.testing.expectEqualStrings("export function createSession(userId: string) {", hit.preview);
    try std.testing.expect(!hit.preview_truncated);
    try std.testing.expectEqual(@as(u16, 1), results.hits[2].file_index);
    try std.testing.expectEqual(@as(u32, 0), results.malformed_lines);
    try std.testing.expect(!results.hits_truncated);
    try std.testing.expect(!results.files_truncated);
    try std.testing.expect(!results.output_truncated);
}

test "parser bounds preview to 200 bytes and flags truncation" {
    const results = try std.testing.allocator.create(Results);
    defer std.testing.allocator.destroy(results);
    results.* = .{};
    var input: [512]u8 = undefined;
    const head = "a.ts\x001:1:";
    @memcpy(input[0..head.len], head);
    @memset(input[head.len..][0..300], 'x');
    input[head.len + 300] = '\n';
    results.parse(input[0 .. head.len + 301], 0, false);

    try std.testing.expectEqual(@as(u32, 1), results.hit_count);
    try std.testing.expectEqual(max_preview, results.hits[0].preview.len);
    try std.testing.expect(results.hits[0].preview_truncated);
}

test "parser enforces global hit budget and sets hits_truncated" {
    const results = try std.testing.allocator.create(Results);
    defer std.testing.allocator.destroy(results);
    results.* = .{};
    var buf: [8 * 1024]u8 = undefined;
    var len: usize = 0;
    var i: u32 = 1;
    while (i <= 10) : (i += 1) {
        const line = std.fmt.bufPrint(buf[len..], "f.ts\x00{d}:1:match {d}\n", .{ i, i }) catch unreachable;
        len += line.len;
    }
    results.parse(buf[0..len], 4, false);
    try std.testing.expectEqual(@as(u32, 4), results.hit_count);
    try std.testing.expect(results.hits_truncated);
    try std.testing.expectEqual(@as(u32, 4), results.hits[3].line);

    // Exactly at budget: not truncated.
    results.parse(buf[0..len], 10, false);
    try std.testing.expectEqual(@as(u32, 10), results.hit_count);
    try std.testing.expect(!results.hits_truncated);
}

test "parser drops hits past file capacity and sets files_truncated" {
    const results = try std.testing.allocator.create(Results);
    defer std.testing.allocator.destroy(results);
    results.* = .{};
    var buf: [8 * 1024]u8 = undefined;
    var len: usize = 0;
    var i: u32 = 0;
    while (i < max_files + 3) : (i += 1) {
        const line = std.fmt.bufPrint(buf[len..], "dir/file_{d}.ts\x001:1:m\n", .{i}) catch unreachable;
        len += line.len;
    }
    results.parse(buf[0..len], 0, false);
    try std.testing.expectEqual(@as(u16, max_files), results.file_count);
    try std.testing.expectEqual(@as(u32, max_files), results.hit_count);
    try std.testing.expect(results.files_truncated);
    try std.testing.expect(!results.hits_truncated);
}

test "parser survives garbage and partial lines without corrupting results" {
    const results = try std.testing.allocator.create(Results);
    defer std.testing.allocator.destroy(results);
    results.* = .{};
    var long_path_line: [max_rel_path + 32]u8 = undefined;
    @memset(long_path_line[0 .. max_rel_path + 1], 'p');
    const tail = "\x001:1:x";
    @memcpy(long_path_line[max_rel_path + 1 ..][0..tail.len], tail);

    var buf: [4 * 1024]u8 = undefined;
    var len: usize = 0;
    const pieces = [_][]const u8{
        "no nul byte in this line at all\n",
        "a.ts\x00notanumber:1:text\n",
        "a.ts\x001:notanumber:text\n",
        "a.ts\x001-missing-colons\n",
        "a.ts\x001:1\n", // no second colon
        "\x001:1:empty path\n",
        "a.ts\x000:0:zero line and column\n",
        "good.ts\x003:7:kept hit\n",
    };
    for (pieces) |piece| {
        @memcpy(buf[len..][0..piece.len], piece);
        len += piece.len;
    }
    @memcpy(buf[len..][0 .. max_rel_path + 1 + tail.len], long_path_line[0 .. max_rel_path + 1 + tail.len]);
    len += max_rel_path + 1 + tail.len;
    const partial = "\ncut.ts\x009:2:stream died here"; // no trailing newline
    @memcpy(buf[len..][0..partial.len], partial);
    len += partial.len;

    results.parse(buf[0..len], 0, true);
    try std.testing.expectEqual(@as(u32, 8), results.malformed_lines);
    try std.testing.expectEqual(@as(u32, 2), results.hit_count);
    try std.testing.expectEqualStrings("good.ts", results.filePath(results.hits[0].file_index));
    try std.testing.expectEqual(@as(u32, 3), results.hits[0].line);
    try std.testing.expectEqual(@as(u32, 7), results.hits[0].column);
    try std.testing.expectEqualStrings("kept hit", results.hits[0].preview);
    // Partial trailing line still parses bounded; stream flag is honest.
    try std.testing.expectEqualStrings("cut.ts", results.filePath(results.hits[1].file_index));
    try std.testing.expect(results.output_truncated);
}

test "parser handles empty input and reuse via clear" {
    const results = try std.testing.allocator.create(Results);
    defer std.testing.allocator.destroy(results);
    results.* = .{};
    results.parse(captured_fixture, 0, false);
    try std.testing.expect(results.hit_count > 0);
    results.parse("", 0, false);
    try std.testing.expectEqual(@as(u32, 0), results.hit_count);
    try std.testing.expectEqual(@as(u16, 0), results.file_count);
    try std.testing.expectEqual(@as(u32, 0), results.malformed_lines);
}

// ---------------------------------------------------------------------------
// Tests — availability probe and real single-shot searches (needs rg + the
// acme-dashboard fixture, same assumptions as search.zig / git_status.zig)
// ---------------------------------------------------------------------------

/// End-to-end tests spawn the real binary; environments without ripgrep
/// (e.g. stock CI runners) skip them honestly. Unit tests always run.
fn skipUnlessRipgrep() !void {
    var probe: Probe = .{};
    if (probe.ensure(std.testing.io) != .available) return error.SkipZigTest;
}

test "probe detects installed ripgrep once and caches the verdict" {
    try skipUnlessRipgrep();
    var probe: Probe = .{};
    try std.testing.expectEqual(Availability.unknown, probe.state);
    try std.testing.expectEqual(Availability.available, probe.ensure(std.testing.io));
    try std.testing.expect(std.mem.startsWith(u8, probe.version(), "ripgrep"));
    try std.testing.expectEqual(Availability.available, probe.ensure(std.testing.io));
    probe.reset();
    try std.testing.expectEqual(Availability.unknown, probe.state);
}

test "probe reports missing binary as unavailable without crashing" {
    var probe: Probe = .{ .exe = "rg-definitely-not-installed-velocity" };
    try std.testing.expectEqual(Availability.unavailable, probe.ensure(std.testing.io));
    try std.testing.expectEqual(@as(usize, 0), probe.version().len);
    // Cached: stays unavailable without another spawn attempt.
    try std.testing.expectEqual(Availability.unavailable, probe.ensure(std.testing.io));
}

test "end-to-end literal search on fixture finds createSession with column" {
    try skipUnlessRipgrep();
    const results = try std.testing.allocator.create(Results);
    defer std.testing.allocator.destroy(results);
    results.* = .{};
    var probe: Probe = .{};
    const status = runSearch(results, &probe, std.testing.io, "fixtures/acme-dashboard", "createSession", .{});
    try std.testing.expect(results.hit_count > 0);
    try std.testing.expect(std.mem.indexOf(u8, status, "hits") != null);
    var found_def = false;
    for (results.hitsSlice()) |hit| {
        const path = results.filePath(hit.file_index);
        if (std.mem.indexOf(u8, path, "auth.ts") != null and hit.line == 1) {
            try std.testing.expectEqual(@as(u32, 17), hit.column);
            try std.testing.expect(std.mem.indexOf(u8, hit.preview, "createSession") != null);
            found_def = true;
        }
    }
    try std.testing.expect(found_def);
}

test "end-to-end search honors exclude glob and reports no matches" {
    try skipUnlessRipgrep();
    const results = try std.testing.allocator.create(Results);
    defer std.testing.allocator.destroy(results);
    results.* = .{};
    var probe: Probe = .{};
    const excluded = runSearch(results, &probe, std.testing.io, "fixtures/acme-dashboard", "createSession", .{
        .exclude_glob = "*.ts*",
    });
    try std.testing.expectEqualStrings("no matches", excluded);
    try std.testing.expectEqual(@as(u32, 0), results.hit_count);

    const missing = runSearch(results, &probe, std.testing.io, "fixtures/acme-dashboard", "velocity-string-that-matches-nothing", .{});
    try std.testing.expectEqualStrings("no matches", missing);
}

test "end-to-end guards: no workspace, unavailable rg, empty query" {
    const results = try std.testing.allocator.create(Results);
    defer std.testing.allocator.destroy(results);
    results.* = .{};
    var probe: Probe = .{};
    try std.testing.expectEqualStrings("no workspace", runSearch(results, &probe, std.testing.io, "", "q", .{}));

    var missing_probe: Probe = .{ .exe = "rg-definitely-not-installed-velocity" };
    try std.testing.expectEqualStrings(
        "ripgrep unavailable",
        runSearch(results, &missing_probe, std.testing.io, "fixtures/acme-dashboard", "q", .{}),
    );

    try skipUnlessRipgrep();
    try std.testing.expectEqualStrings(
        "empty query",
        runSearch(results, &probe, std.testing.io, "fixtures/acme-dashboard", "   ", .{}),
    );
}

test "end-to-end whole word and case sensitivity change results" {
    try skipUnlessRipgrep();
    const results = try std.testing.allocator.create(Results);
    defer std.testing.allocator.destroy(results);
    results.* = .{};
    var probe: Probe = .{};
    _ = runSearch(results, &probe, std.testing.io, "fixtures/acme-dashboard", "TODO", .{ .case_sensitive = true });
    const sensitive_hits = results.hit_count;
    try std.testing.expect(sensitive_hits > 0);
    _ = runSearch(results, &probe, std.testing.io, "fixtures/acme-dashboard", "todo", .{});
    try std.testing.expect(results.hit_count >= sensitive_hits);

    _ = runSearch(results, &probe, std.testing.io, "fixtures/acme-dashboard", "create", .{ .whole_word = true });
    const word_hits = results.hit_count;
    _ = runSearch(results, &probe, std.testing.io, "fixtures/acme-dashboard", "create", .{});
    try std.testing.expect(results.hit_count >= word_hits);
}
