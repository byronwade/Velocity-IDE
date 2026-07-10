//! Copyright (c) Velocity IDE contributors.
//! Bounded hunk-level staging engine for the SCM panel.
//!
//! `parseHunks` indexes the single-file unified diff text that
//! `git_status.GitBuffers.loadDiff` already holds (offsets + lengths into the
//! caller's buffer, no copies) and `buildHunkPatch` reconstructs a minimal
//! valid patch (original `---`/`+++` headers + one selected hunk) that
//! `git apply` accepts. Hunk offsets are never renumbered: a single original
//! hunk applies cleanly with its original `@@` header because the base file
//! is unchanged.
//!
//! Direction contract for the integrator (see `applyArgv`):
//!   stage   = `git apply --cached <patch>`           patch built from the
//!             UNSTAGED diff (`git diff -- <path>`, loadDiff mode .unstaged)
//!   unstage = `git apply --cached --reverse <patch>` patch built from the
//!             STAGED diff (`git diff --cached -- <path>`, mode .staged)
//!   discard = `git apply --reverse <patch>`          patch built from the
//!             UNSTAGED diff. DESTRUCTIVE: rewrites the working tree; the
//!             caller must confirm with the user before running it.
//!
//! Safety rules enforced here:
//!   - A truncated final hunk (loadDiff caps output at max_diff_bytes) is
//!     marked unusable; staging it would corrupt the index. When the caller
//!     reports `input_truncated`, the last indexed hunk is refused even if
//!     its line counts happen to balance, because a trailing
//!     "\ No newline at end of file" marker may have been cut at a line
//!     boundary.
//!   - Rename diffs are flagged and refused (`error.RenameUnsupported`); the
//!     integrator should fall back to whole-file stage/unstage for renames.
//!   - Binary diffs and malformed input yield an invalid index, never a crash.

const std = @import("std");

pub const max_hunks: usize = 32;

/// One indexed hunk. All offsets/lengths address the caller's diff text.
pub const Hunk = struct {
    /// Byte offset of the `@@` header line.
    header_off: usize = 0,
    /// Header line length including its trailing newline.
    header_len: usize = 0,
    /// Byte offset of the first body line (immediately after the header).
    body_off: usize = 0,
    /// Body length in bytes, including trailing newline of the last line and
    /// any "\ No newline at end of file" markers.
    body_len: usize = 0,
    old_start: u32 = 0,
    old_count: u32 = 0,
    new_start: u32 = 0,
    new_count: u32 = 0,
    /// False when the hunk is truncated or malformed. `buildHunkPatch`
    /// refuses unusable hunks.
    usable: bool = false,
};

pub const HunkIndex = struct {
    hunks: [max_hunks]Hunk = [_]Hunk{.{}} ** max_hunks,
    hunk_count: u32 = 0,
    /// Span of the original file header: the `--- ` line through the end of
    /// the `+++ ` line (inclusive of its newline).
    file_header_off: usize = 0,
    file_header_len: usize = 0,
    has_file_header: bool = false,
    /// Diff carries rename metadata ("rename from/to", "similarity index").
    is_rename: bool = false,
    is_binary: bool = false,
    /// The diff text contained more than max_hunks hunks; extra hunks were
    /// not indexed (the first max_hunks remain individually valid).
    hunks_overflow: bool = false,
    /// Mirrors the caller's truncation report (loadDiff diff_truncated).
    input_truncated: bool = false,
    /// True when the file header and at least one hunk were indexed.
    valid: bool = false,
    status: []const u8 = "no hunks",

    pub fn hunksSlice(self: *const HunkIndex) []const Hunk {
        return self.hunks[0..self.hunk_count];
    }
};

const Line = struct {
    off: usize,
    text: []const u8,
    terminated: bool,
};

const LineIter = struct {
    data: []const u8,
    pos: usize = 0,

    fn next(self: *LineIter) ?Line {
        if (self.pos >= self.data.len) return null;
        const start = self.pos;
        if (std.mem.indexOfScalarPos(u8, self.data, start, '\n')) |nl| {
            self.pos = nl + 1;
            return .{ .off = start, .text = self.data[start..nl], .terminated = true };
        }
        self.pos = self.data.len;
        return .{ .off = start, .text = self.data[start..], .terminated = false };
    }

    fn peek(self: *LineIter) ?Line {
        const saved = self.pos;
        defer self.pos = saved;
        return self.next();
    }
};

const Range = struct { start: u32, count: u32 };

fn parseRange(spec: []const u8) ?Range {
    if (std.mem.indexOfScalar(u8, spec, ',')) |comma| {
        const start = std.fmt.parseInt(u32, spec[0..comma], 10) catch return null;
        const count = std.fmt.parseInt(u32, spec[comma + 1 ..], 10) catch return null;
        return .{ .start = start, .count = count };
    }
    const start = std.fmt.parseInt(u32, spec, 10) catch return null;
    // "@@ -a +c @@" means a count of exactly 1.
    return .{ .start = start, .count = 1 };
}

const HeaderNums = struct { old: Range, new: Range };

fn parseHunkHeader(line: []const u8) ?HeaderNums {
    if (!std.mem.startsWith(u8, line, "@@ -")) return null;
    const rest = line[4..];
    const plus = std.mem.indexOf(u8, rest, " +") orelse return null;
    const old = parseRange(rest[0..plus]) orelse return null;
    const tail = rest[plus + 2 ..];
    const close = std.mem.indexOf(u8, tail, " @@") orelse return null;
    const new = parseRange(tail[0..close]) orelse return null;
    return .{ .old = old, .new = new };
}

/// Index the hunks of a single-file `git diff` unified output. Never copies:
/// every hunk records offsets into `diff_text`, which must stay alive and
/// unmodified while the index is used. `input_truncated` is the caller's
/// report that the diff was byte-capped (GitBuffers.diff_truncated); it
/// forces the final indexed hunk to be unusable.
pub fn parseHunks(diff_text: []const u8, input_truncated: bool) HunkIndex {
    var index: HunkIndex = .{ .input_truncated = input_truncated };
    var it: LineIter = .{ .data = diff_text };

    // --- Header phase: everything before the first "@@" line. ---
    var seen_minus = false;
    var minus_off: usize = 0;
    while (it.peek()) |line| {
        const text = line.text;
        if (std.mem.startsWith(u8, text, "@@ ")) break;
        _ = it.next();
        if (std.mem.startsWith(u8, text, "--- ")) {
            seen_minus = true;
            minus_off = line.off;
            index.has_file_header = false;
        } else if (seen_minus and std.mem.startsWith(u8, text, "+++ ")) {
            if (!line.terminated) {
                index.status = "truncated file header";
                return index;
            }
            index.file_header_off = minus_off;
            index.file_header_len = it.pos - minus_off;
            index.has_file_header = true;
        } else if (std.mem.startsWith(u8, text, "rename from") or
            std.mem.startsWith(u8, text, "rename to") or
            std.mem.startsWith(u8, text, "similarity index"))
        {
            index.is_rename = true;
        } else if (std.mem.startsWith(u8, text, "Binary files") or
            std.mem.startsWith(u8, text, "GIT binary patch"))
        {
            index.is_binary = true;
            index.status = "binary diff";
            return index;
        }
        // "diff --git", "index", mode lines, and unknown prose are skipped.
    }
    if (!index.has_file_header) {
        index.status = "no file header";
        return index;
    }

    // --- Hunk phase. ---
    parse: while (it.peek()) |line| {
        if (!std.mem.startsWith(u8, line.text, "@@ ")) {
            // A second "diff " section (multi-file input) or stray line ends
            // indexing; already-indexed hunks remain individually verified.
            index.status = if (std.mem.startsWith(u8, line.text, "diff "))
                "stopped at second file"
            else
                "stopped at stray line";
            break;
        }
        if (index.hunk_count >= max_hunks) {
            index.hunks_overflow = true;
            index.status = "hunk limit reached";
            break;
        }
        _ = it.next();
        const nums = parseHunkHeader(line.text) orelse {
            index.status = "bad hunk header";
            break;
        };
        var hunk: Hunk = .{
            .header_off = line.off,
            .header_len = it.pos - line.off,
            .old_start = nums.old.start,
            .old_count = nums.old.count,
            .new_start = nums.new.start,
            .new_count = nums.new.count,
        };
        hunk.body_off = it.pos;
        if (!line.terminated) {
            // Header itself was cut by the byte cap.
            index.hunks[index.hunk_count] = hunk;
            index.hunk_count += 1;
            index.status = "truncated hunk";
            break;
        }

        var old_seen: u32 = 0;
        var new_seen: u32 = 0;
        var terminated = true;
        while (it.peek()) |body| {
            const text = body.text;
            if (text.len == 0) {
                // Tolerate a bare empty line as an empty context line (some
                // transports strip the leading space).
                old_seen += 1;
                new_seen += 1;
            } else switch (text[0]) {
                ' ' => {
                    old_seen += 1;
                    new_seen += 1;
                },
                '-' => old_seen += 1,
                '+' => new_seen += 1,
                '\\' => {}, // "\ No newline at end of file" counts as neither.
                else => break, // next "@@", "diff ", or stray line
            }
            _ = it.next();
            terminated = body.terminated;
        }
        hunk.body_len = it.pos - hunk.body_off;
        // A hunk is only usable when its body is complete: every declared
        // old/new line is present and the final line is newline-terminated
        // (git diff output always is; a missing newline means the byte cap
        // cut the hunk mid-line).
        hunk.usable = terminated and old_seen == hunk.old_count and new_seen == hunk.new_count;
        index.hunks[index.hunk_count] = hunk;
        index.hunk_count += 1;
        if (!hunk.usable) {
            index.status = "truncated hunk";
            break :parse;
        }
    }

    // A byte-capped diff can be cut exactly at a line boundary, dropping a
    // trailing "\ No newline at end of file" marker (or whole later lines)
    // without unbalancing the counts. Refuse the last hunk outright.
    if (input_truncated and index.hunk_count > 0) {
        index.hunks[index.hunk_count - 1].usable = false;
        index.status = "input truncated";
    }

    index.valid = index.hunk_count > 0;
    if (index.valid and std.mem.eql(u8, index.status, "no hunks")) {
        index.status = "hunks indexed";
    }
    return index;
}

pub const BuildError = error{
    /// The index is not valid or does not match `diff_text`.
    InvalidIndex,
    HunkOutOfRange,
    /// The hunk is truncated or malformed; applying it would corrupt state.
    HunkUnusable,
    /// Rename diffs need whole-file staging; a lone hunk patch would apply
    /// under mismatched old/new paths.
    RenameUnsupported,
    /// `out_buf` is too small for the reconstructed patch.
    OutputOverflow,
};

/// Reconstruct a minimal single-hunk patch: original `---`/`+++` file header
/// followed by the selected hunk, byte-for-byte from `diff_text` (offsets are
/// never renumbered). `diff_text` must be the exact text `parseHunks` saw.
/// `out_buf` is caller-owned; the returned slice aliases it.
pub fn buildHunkPatch(
    diff_text: []const u8,
    index: *const HunkIndex,
    hunk_ordinal: usize,
    out_buf: []u8,
) BuildError![]const u8 {
    if (!index.valid or !index.has_file_header) return error.InvalidIndex;
    if (index.is_rename) return error.RenameUnsupported;
    if (hunk_ordinal >= index.hunk_count) return error.HunkOutOfRange;
    const hunk = index.hunks[hunk_ordinal];
    if (!hunk.usable) return error.HunkUnusable;

    const header_end = index.file_header_off + index.file_header_len;
    const hunk_end = hunk.body_off + hunk.body_len;
    if (header_end > diff_text.len or hunk_end > diff_text.len) return error.InvalidIndex;
    if (hunk.header_off + hunk.header_len != hunk.body_off) return error.InvalidIndex;

    const total = index.file_header_len + hunk.header_len + hunk.body_len;
    if (total > out_buf.len) return error.OutputOverflow;
    @memcpy(out_buf[0..index.file_header_len], diff_text[index.file_header_off..header_end]);
    @memcpy(
        out_buf[index.file_header_len..][0 .. hunk.header_len + hunk.body_len],
        diff_text[hunk.header_off..hunk_end],
    );
    return out_buf[0..total];
}

pub const HunkOp = enum {
    /// Apply the hunk (from the unstaged diff) to the index.
    stage,
    /// Reverse the hunk (from the STAGED diff, `git diff --cached`) out of
    /// the index; the working tree is untouched.
    unstage,
    /// Reverse the hunk (from the unstaged diff) out of the working tree.
    /// DESTRUCTIVE — the caller must confirm with the user first.
    discard,
};

/// Fixed argv storage for `std.process.run`-style spawning (no shell).
pub const ApplyArgv = struct {
    buf: [5][]const u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const ApplyArgv) []const []const u8 {
        return self.buf[0..self.len];
    }
};

/// Build the `git apply` argv for one operation. `patch_path` is the file the
/// integrator wrote the `buildHunkPatch` output to (std.process.run offers no
/// stdin pipe, so the patch travels via a file), resolved relative to the
/// repository root the command runs in.
pub fn applyArgv(op: HunkOp, patch_path: []const u8) ApplyArgv {
    var argv: ApplyArgv = .{};
    const words: []const []const u8 = switch (op) {
        .stage => &.{ "git", "apply", "--cached", patch_path },
        .unstage => &.{ "git", "apply", "--cached", "--reverse", patch_path },
        .discard => &.{ "git", "apply", "--reverse", patch_path },
    };
    for (words, 0..) |word, i| argv.buf[i] = word;
    argv.len = words.len;
    return argv;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const sample_diff =
    "diff --git a/notes.txt b/notes.txt\n" ++
    "index 1111111..2222222 100644\n" ++
    "--- a/notes.txt\n" ++
    "+++ b/notes.txt\n" ++
    "@@ -1,3 +1,3 @@\n" ++
    "-one\n" ++
    "+ONE\n" ++
    " two\n" ++
    " three\n" ++
    "@@ -10,3 +10,4 @@\n" ++
    " ten\n" ++
    "-eleven\n" ++
    "+ELEVEN\n" ++
    "+eleven-b\n" ++
    " twelve\n";

test "parse indexes hunks with offsets into the caller's text" {
    const index = parseHunks(sample_diff, false);
    try std.testing.expect(index.valid);
    try std.testing.expectEqualStrings("hunks indexed", index.status);
    try std.testing.expectEqual(@as(u32, 2), index.hunk_count);
    try std.testing.expect(index.has_file_header);
    try std.testing.expect(!index.is_rename);
    try std.testing.expect(!index.hunks_overflow);

    const header = sample_diff[index.file_header_off..][0..index.file_header_len];
    try std.testing.expectEqualStrings("--- a/notes.txt\n+++ b/notes.txt\n", header);

    const first = index.hunks[0];
    try std.testing.expect(first.usable);
    try std.testing.expectEqual(@as(u32, 1), first.old_start);
    try std.testing.expectEqual(@as(u32, 3), first.old_count);
    try std.testing.expectEqualStrings(
        "@@ -1,3 +1,3 @@\n",
        sample_diff[first.header_off..][0..first.header_len],
    );
    try std.testing.expectEqualStrings(
        "-one\n+ONE\n two\n three\n",
        sample_diff[first.body_off..][0..first.body_len],
    );

    const second = index.hunks[1];
    try std.testing.expect(second.usable);
    try std.testing.expectEqual(@as(u32, 10), second.old_start);
    try std.testing.expectEqual(@as(u32, 3), second.old_count);
    try std.testing.expectEqual(@as(u32, 10), second.new_start);
    try std.testing.expectEqual(@as(u32, 4), second.new_count);
}

test "build patch keeps original header and never renumbers" {
    const index = parseHunks(sample_diff, false);
    var out: [512]u8 = undefined;
    const patch = try buildHunkPatch(sample_diff, &index, 1, &out);
    try std.testing.expectEqualStrings(
        "--- a/notes.txt\n+++ b/notes.txt\n" ++
            "@@ -10,3 +10,4 @@\n ten\n-eleven\n+ELEVEN\n+eleven-b\n twelve\n",
        patch,
    );
    var tiny: [16]u8 = undefined;
    try std.testing.expectError(error.OutputOverflow, buildHunkPatch(sample_diff, &index, 1, &tiny));
    try std.testing.expectError(error.HunkOutOfRange, buildHunkPatch(sample_diff, &index, 2, &out));
}

test "byte-capped diff marks the cut hunk unusable and refuses it" {
    // Cut inside the second hunk body (drop " twelve\n" and part of the
    // previous line) - the line counts no longer balance.
    const cut = sample_diff[0 .. sample_diff.len - 10];
    const index = parseHunks(cut, false);
    try std.testing.expectEqual(@as(u32, 2), index.hunk_count);
    try std.testing.expect(index.hunks[0].usable);
    try std.testing.expect(!index.hunks[1].usable);
    var out: [512]u8 = undefined;
    try std.testing.expectError(error.HunkUnusable, buildHunkPatch(cut, &index, 1, &out));
    _ = try buildHunkPatch(cut, &index, 0, &out);

    // Even a balanced final hunk is refused when the caller reports the
    // input was byte-capped (a trailing "\ No newline" marker may be gone).
    const flagged = parseHunks(sample_diff, true);
    try std.testing.expect(flagged.hunks[0].usable);
    try std.testing.expect(!flagged.hunks[1].usable);
    try std.testing.expectError(error.HunkUnusable, buildHunkPatch(sample_diff, &flagged, 1, &out));
}

test "malformed and hostile inputs never crash" {
    var out: [128]u8 = undefined;

    const empty = parseHunks("", false);
    try std.testing.expect(!empty.valid);
    try std.testing.expectError(error.InvalidIndex, buildHunkPatch("", &empty, 0, &out));

    const prose = parseHunks("hello\nworld\n", false);
    try std.testing.expect(!prose.valid);
    try std.testing.expectEqualStrings("no file header", prose.status);

    const bad_header = parseHunks("--- a/f\n+++ b/f\n@@ nonsense @@\n-x\n", false);
    try std.testing.expect(!bad_header.valid);
    try std.testing.expectEqualStrings("bad hunk header", bad_header.status);

    const binary = parseHunks(
        "diff --git a/x b/x\nBinary files a/x and b/x differ\n",
        false,
    );
    try std.testing.expect(!binary.valid);
    try std.testing.expect(binary.is_binary);

    const header_only = parseHunks("--- a/f\n+++ b/f\n", false);
    try std.testing.expect(!header_only.valid);

    const no_newline_header = parseHunks("--- a/f\n+++ b/f", false);
    try std.testing.expect(!no_newline_header.valid);
    try std.testing.expectEqualStrings("truncated file header", no_newline_header.status);

    // Header cut mid-line by the byte cap.
    const cut_header = parseHunks("--- a/f\n+++ b/f\n@@ -1,2 +1", false);
    try std.testing.expect(!cut_header.valid);
}

test "rename diffs are flagged and refused" {
    const rename_diff =
        "diff --git a/old.txt b/new.txt\n" ++
        "similarity index 90%\n" ++
        "rename from old.txt\n" ++
        "rename to new.txt\n" ++
        "--- a/old.txt\n" ++
        "+++ b/new.txt\n" ++
        "@@ -1,1 +1,1 @@\n" ++
        "-a\n" ++
        "+b\n";
    const index = parseHunks(rename_diff, false);
    try std.testing.expect(index.is_rename);
    try std.testing.expect(index.valid);
    var out: [256]u8 = undefined;
    try std.testing.expectError(error.RenameUnsupported, buildHunkPatch(rename_diff, &index, 0, &out));
}

test "omitted counts default to one and no-newline markers do not count" {
    const diff =
        "--- a/f\n+++ b/f\n" ++
        "@@ -3 +3 @@\n" ++
        "-c\n" ++
        "\\ No newline at end of file\n" ++
        "+C\n" ++
        "\\ No newline at end of file\n";
    const index = parseHunks(diff, false);
    try std.testing.expectEqual(@as(u32, 1), index.hunk_count);
    const hunk = index.hunks[0];
    try std.testing.expect(hunk.usable);
    try std.testing.expectEqual(@as(u32, 1), hunk.old_count);
    try std.testing.expectEqual(@as(u32, 1), hunk.new_count);
    var out: [256]u8 = undefined;
    const patch = try buildHunkPatch(diff, &index, 0, &out);
    try std.testing.expect(std.mem.indexOf(u8, patch, "\\ No newline at end of file") != null);
}

test "hunk index is bounded at max_hunks and flags overflow" {
    var big: [8192]u8 = undefined;
    const header = "--- a/f\n+++ b/f\n";
    @memcpy(big[0..header.len], header);
    var used: usize = header.len;
    var n: u32 = 1;
    while (n <= 40) : (n += 1) {
        const chunk = try std.fmt.bufPrint(
            big[used..],
            "@@ -{d},1 +{d},1 @@\n-x{d}\n+y{d}\n",
            .{ n * 10, n * 10, n, n },
        );
        used += chunk.len;
    }
    const index = parseHunks(big[0..used], false);
    try std.testing.expectEqual(@as(u32, max_hunks), index.hunk_count);
    try std.testing.expect(index.hunks_overflow);
    for (index.hunksSlice()) |hunk| try std.testing.expect(hunk.usable);
}

test "apply argv encodes the three directions" {
    const stage = applyArgv(.stage, "p.patch");
    try std.testing.expectEqual(@as(usize, 4), stage.slice().len);
    try std.testing.expectEqualStrings("--cached", stage.slice()[2]);
    try std.testing.expectEqualStrings("p.patch", stage.slice()[3]);

    const unstage = applyArgv(.unstage, "p.patch");
    try std.testing.expectEqual(@as(usize, 5), unstage.slice().len);
    try std.testing.expectEqualStrings("--cached", unstage.slice()[2]);
    try std.testing.expectEqualStrings("--reverse", unstage.slice()[3]);

    const discard = applyArgv(.discard, "p.patch");
    try std.testing.expectEqual(@as(usize, 4), discard.slice().len);
    try std.testing.expectEqualStrings("--reverse", discard.slice()[2]);
}

// --- End-to-end proof against a real git repository. -----------------------

fn runTestGit(cwd: []const u8, argv: []const []const u8) !void {
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdout_limit = .limited(8192),
        .stderr_limit = .limited(8192),
    });
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }
    switch (result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

fn gitCapture(cwd: []const u8, argv: []const []const u8, out: []u8) ![]const u8 {
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdout_limit = .limited(out.len),
        .stderr_limit = .limited(8192),
    });
    defer {
        std.testing.allocator.free(result.stdout);
        std.testing.allocator.free(result.stderr);
    }
    switch (result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
    const n = @min(result.stdout.len, out.len);
    @memcpy(out[0..n], result.stdout[0..n]);
    return out[0..n];
}

fn initTestRepo(tmp: *std.testing.TmpDir, path_buf: []u8) ![]const u8 {
    const cwd = try std.fmt.bufPrint(path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try runTestGit(cwd, &.{ "git", "init", "-q" });
    try runTestGit(cwd, &.{ "git", "config", "user.email", "scm-test@example.invalid" });
    try runTestGit(cwd, &.{ "git", "config", "user.name", "SCM Test" });
    return cwd;
}

fn applyPatch(tmp: *std.testing.TmpDir, cwd: []const u8, op: HunkOp, patch: []const u8) !void {
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "hunk.patch", .data = patch });
    const argv = applyArgv(op, "hunk.patch");
    try runTestGit(cwd, argv.slice());
}

const regions_original =
    "l01\nl02\nalpha\nl04\nl05\nl06\nl07\nl08\nl09\nl10\n" ++
    "bravo\nl12\nl13\nl14\nl15\nl16\nl17\nl18\n" ++
    "charlie\nl20\nl21\n";
const regions_modified =
    "l01\nl02\nALPHA\nl04\nl05\nl06\nl07\nl08\nl09\nl10\n" ++
    "BRAVO\nl12\nl13\nl14\nl15\nl16\nl17\nl18\n" ++
    "CHARLIE\nl20\nl21\n";

test "stage exactly one middle hunk via git apply --cached, then reverse-unstage it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [128]u8 = undefined;
    const cwd = try initTestRepo(&tmp, &path_buf);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "regions.txt", .data = regions_original });
    try runTestGit(cwd, &.{ "git", "add", "--", "regions.txt" });
    try runTestGit(cwd, &.{ "git", "commit", "-q", "-m", "initial" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "regions.txt", .data = regions_modified });

    // Parse the real unstaged diff: three well-separated hunks.
    var diff_buf: [8192]u8 = undefined;
    const diff = try gitCapture(cwd, &.{ "git", "diff", "--", "regions.txt" }, &diff_buf);
    const index = parseHunks(diff, false);
    try std.testing.expect(index.valid);
    try std.testing.expectEqual(@as(u32, 3), index.hunk_count);
    for (index.hunksSlice()) |hunk| try std.testing.expect(hunk.usable);

    // Stage ONLY the middle hunk.
    var patch_buf: [4096]u8 = undefined;
    const patch = try buildHunkPatch(diff, &index, 1, &patch_buf);
    try std.testing.expect(std.mem.indexOf(u8, patch, "+BRAVO") != null);
    try std.testing.expect(std.mem.indexOf(u8, patch, "ALPHA") == null);
    try applyPatch(&tmp, cwd, .stage, patch);

    // Precisely the middle region is staged...
    var staged_buf: [8192]u8 = undefined;
    const staged = try gitCapture(cwd, &.{ "git", "diff", "--cached", "--", "regions.txt" }, &staged_buf);
    try std.testing.expect(std.mem.indexOf(u8, staged, "+BRAVO") != null);
    try std.testing.expect(std.mem.indexOf(u8, staged, "-bravo") != null);
    try std.testing.expect(std.mem.indexOf(u8, staged, "ALPHA") == null);
    try std.testing.expect(std.mem.indexOf(u8, staged, "CHARLIE") == null);

    // ...and the other two regions remain unstaged only.
    var unstaged_buf: [8192]u8 = undefined;
    const unstaged = try gitCapture(cwd, &.{ "git", "diff", "--", "regions.txt" }, &unstaged_buf);
    try std.testing.expect(std.mem.indexOf(u8, unstaged, "+ALPHA") != null);
    try std.testing.expect(std.mem.indexOf(u8, unstaged, "+CHARLIE") != null);
    try std.testing.expect(std.mem.indexOf(u8, unstaged, "BRAVO") == null);

    // Reverse-unstage: extract the hunk from the STAGED diff and reverse it
    // out of the index. The working tree keeps all three edits.
    const staged_index = parseHunks(staged, false);
    try std.testing.expectEqual(@as(u32, 1), staged_index.hunk_count);
    var unstage_buf: [4096]u8 = undefined;
    const unstage_patch = try buildHunkPatch(staged, &staged_index, 0, &unstage_buf);
    try applyPatch(&tmp, cwd, .unstage, unstage_patch);

    var after_buf: [8192]u8 = undefined;
    const staged_after = try gitCapture(cwd, &.{ "git", "diff", "--cached", "--", "regions.txt" }, &after_buf);
    try std.testing.expectEqual(@as(usize, 0), staged_after.len);
    var tree_buf: [8192]u8 = undefined;
    const tree_after = try gitCapture(cwd, &.{ "git", "diff", "--", "regions.txt" }, &tree_buf);
    try std.testing.expect(std.mem.indexOf(u8, tree_after, "+ALPHA") != null);
    try std.testing.expect(std.mem.indexOf(u8, tree_after, "+BRAVO") != null);
    try std.testing.expect(std.mem.indexOf(u8, tree_after, "+CHARLIE") != null);
}

test "discard one hunk from the working tree via git apply --reverse" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [128]u8 = undefined;
    const cwd = try initTestRepo(&tmp, &path_buf);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "regions.txt", .data = regions_original });
    try runTestGit(cwd, &.{ "git", "add", "--", "regions.txt" });
    try runTestGit(cwd, &.{ "git", "commit", "-q", "-m", "initial" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "regions.txt", .data = regions_modified });

    var diff_buf: [8192]u8 = undefined;
    const diff = try gitCapture(cwd, &.{ "git", "diff", "--", "regions.txt" }, &diff_buf);
    const index = parseHunks(diff, false);
    try std.testing.expectEqual(@as(u32, 3), index.hunk_count);

    // Discard the first hunk (alpha region) only.
    var patch_buf: [4096]u8 = undefined;
    const patch = try buildHunkPatch(diff, &index, 0, &patch_buf);
    try applyPatch(&tmp, cwd, .discard, patch);

    var file_buf: [256]u8 = undefined;
    const contents = try tmp.dir.readFile(std.testing.io, "regions.txt", &file_buf);
    try std.testing.expect(std.mem.indexOf(u8, contents, "alpha") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "ALPHA") == null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "BRAVO") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "CHARLIE") != null);
}

test "file with no trailing newline round-trips through stage and unstage" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [128]u8 = undefined;
    const cwd = try initTestRepo(&tmp, &path_buf);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "tail.txt", .data = "a\nb\nc" });
    try runTestGit(cwd, &.{ "git", "add", "--", "tail.txt" });
    try runTestGit(cwd, &.{ "git", "commit", "-q", "-m", "initial" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "tail.txt", .data = "a\nb\nC" });

    var diff_buf: [8192]u8 = undefined;
    const diff = try gitCapture(cwd, &.{ "git", "diff", "--", "tail.txt" }, &diff_buf);
    const index = parseHunks(diff, false);
    try std.testing.expectEqual(@as(u32, 1), index.hunk_count);
    try std.testing.expect(index.hunks[0].usable);

    var patch_buf: [4096]u8 = undefined;
    const patch = try buildHunkPatch(diff, &index, 0, &patch_buf);
    try std.testing.expect(std.mem.indexOf(u8, patch, "\\ No newline at end of file") != null);
    try applyPatch(&tmp, cwd, .stage, patch);

    // Fully staged: the unstaged diff is empty, the staged diff carries the
    // marker, and the working tree still lacks the trailing newline.
    var unstaged_buf: [8192]u8 = undefined;
    const unstaged = try gitCapture(cwd, &.{ "git", "diff", "--", "tail.txt" }, &unstaged_buf);
    try std.testing.expectEqual(@as(usize, 0), unstaged.len);
    var staged_buf: [8192]u8 = undefined;
    const staged = try gitCapture(cwd, &.{ "git", "diff", "--cached", "--", "tail.txt" }, &staged_buf);
    try std.testing.expect(std.mem.indexOf(u8, staged, "+C") != null);
    try std.testing.expect(std.mem.indexOf(u8, staged, "\\ No newline at end of file") != null);

    // Reverse-unstage from the staged diff restores a clean index.
    const staged_index = parseHunks(staged, false);
    try std.testing.expectEqual(@as(u32, 1), staged_index.hunk_count);
    var unstage_buf: [4096]u8 = undefined;
    const unstage_patch = try buildHunkPatch(staged, &staged_index, 0, &unstage_buf);
    try applyPatch(&tmp, cwd, .unstage, unstage_patch);
    var after_buf: [8192]u8 = undefined;
    const staged_after = try gitCapture(cwd, &.{ "git", "diff", "--cached", "--", "tail.txt" }, &after_buf);
    try std.testing.expectEqual(@as(usize, 0), staged_after.len);

    var file_buf: [64]u8 = undefined;
    const contents = try tmp.dir.readFile(std.testing.io, "tail.txt", &file_buf);
    try std.testing.expectEqualStrings("a\nb\nC", contents);
}
