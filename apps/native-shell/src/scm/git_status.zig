//! Lightweight git status for SCM panel (MVP).
//! Runs `git status --porcelain` via Process Governor bookkeeping + process.run.

const std = @import("std");

pub const max_entries: usize = 64;
pub const max_path: usize = 240;
pub const max_status: usize = 2;

pub const GitEntry = struct {
    id: u32 = 0,
    status: []const u8 = "",
    path: []const u8 = "",
};

pub const GitBuffers = struct {
    entries: [max_entries]GitEntry = [_]GitEntry{.{}} ** max_entries,
    entry_count: u32 = 0,
    status_pool: [max_entries][max_status]u8 = undefined,
    path_pool: [max_entries][max_path]u8 = undefined,
    status_lens: [max_entries]usize = [_]usize{0} ** max_entries,
    path_lens: [max_entries]usize = [_]usize{0} ** max_entries,
    branch_buf: [64]u8 = undefined,
    branch_len: usize = 0,
    summary: []const u8 = "not loaded",
    available: bool = false,
    diff_buf: [8 * 1024]u8 = undefined,
    diff_len: usize = 0,
    diff_status: []const u8 = "—",
    selected_entry_id: u32 = 0,

    pub fn entriesSlice(self: *GitBuffers) []const GitEntry {
        return self.entries[0..self.entry_count];
    }

    pub fn diffText(self: *const GitBuffers) []const u8 {
        return self.diff_buf[0..self.diff_len];
    }

    pub fn branch(self: *const GitBuffers) []const u8 {
        if (self.branch_len == 0) return "unknown";
        return self.branch_buf[0..self.branch_len];
    }

    pub fn clear(self: *GitBuffers) void {
        self.entry_count = 0;
        self.branch_len = 0;
        self.summary = "not loaded";
        self.available = false;
        self.diff_len = 0;
        self.diff_status = "—";
        self.selected_entry_id = 0;
    }

    /// Load a bounded `git diff` / `git diff --no-index` style preview for one path.
    pub fn loadDiff(self: *GitBuffers, io: std.Io, cwd: []const u8, entry_id: u32) void {
        self.diff_len = 0;
        self.selected_entry_id = entry_id;
        var path: []const u8 = "";
        var status: []const u8 = "";
        for (self.entriesSlice()) |e| {
            if (e.id == entry_id) {
                path = e.path;
                status = e.status;
                break;
            }
        }
        if (path.len == 0) {
            self.diff_status = "no entry";
            return;
        }
        if (cwd.len == 0) {
            self.diff_status = "no workspace";
            return;
        }

        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();

        const untracked = status.len > 0 and status[0] == '?';
        const result = if (untracked)
            std.process.run(gpa, io, .{
                .argv = &.{ "git", "diff", "--no-index", "--", "/dev/null", path },
                .cwd = .{ .path = cwd },
                .stdout_limit = .limited(self.diff_buf.len),
                .stderr_limit = .limited(1024),
            })
        else
            std.process.run(gpa, io, .{
                .argv = &.{ "git", "diff", "HEAD", "--", path },
                .cwd = .{ .path = cwd },
                .stdout_limit = .limited(self.diff_buf.len),
                .stderr_limit = .limited(1024),
            });

        const run = result catch {
            self.diff_status = "diff failed";
            return;
        };
        defer {
            gpa.free(run.stdout);
            gpa.free(run.stderr);
        }

        // git diff --no-index exits 1 when files differ; still useful output.
        if (run.stdout.len == 0) {
            self.diff_status = if (untracked) "untracked (empty)" else "no diff";
            const msg = if (untracked) "(untracked file — no HEAD base)" else "(no textual diff)";
            const n = @min(msg.len, self.diff_buf.len);
            @memcpy(self.diff_buf[0..n], msg[0..n]);
            self.diff_len = n;
            return;
        }
        const n = @min(run.stdout.len, self.diff_buf.len);
        @memcpy(self.diff_buf[0..n], run.stdout[0..n]);
        self.diff_len = n;
        self.diff_status = "diff loaded";
    }

    /// True only when `cwd` is itself a usable git work-tree root.
    /// A stub `.git` (e.g. fixture with only HEAD) must not let git walk up to a parent repo.
    fn isGitRoot(io: std.Io, cwd: []const u8) bool {
        if (cwd.len == 0) return false;

        // Prefer a local `.git/config` so incomplete stub dirs are rejected early.
        var config_buf: [512]u8 = undefined;
        if (cwd.len + 12 <= config_buf.len) {
            @memcpy(config_buf[0..cwd.len], cwd);
            @memcpy(config_buf[cwd.len..][0..12], "/.git/config");
            std.Io.Dir.cwd().access(io, config_buf[0 .. cwd.len + 12], .{}) catch return false;
        } else return false;

        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();

        const top_result = std.process.run(gpa, io, .{
            .argv = &.{ "git", "rev-parse", "--show-toplevel" },
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(512),
            .stderr_limit = .limited(256),
        }) catch return false;
        defer {
            gpa.free(top_result.stdout);
            gpa.free(top_result.stderr);
        }
        switch (top_result.term) {
            .exited => |code| if (code != 0) return false,
            else => return false,
        }
        const toplevel = std.mem.trim(u8, top_result.stdout, " \t\r\n");
        if (toplevel.len == 0) return false;

        const abs_result = std.process.run(gpa, io, .{
            .argv = &.{ "realpath", "-m", cwd },
            .stdout_limit = .limited(512),
            .stderr_limit = .limited(256),
        }) catch return false;
        defer {
            gpa.free(abs_result.stdout);
            gpa.free(abs_result.stderr);
        }
        switch (abs_result.term) {
            .exited => |code| if (code != 0) return false,
            else => return false,
        }
        const abs_cwd = std.mem.trim(u8, abs_result.stdout, " \t\r\n");
        return std.mem.eql(u8, toplevel, abs_cwd);
    }

    /// Accept only normalized repository-relative paths. Commands pass this path as a
    /// distinct argv value after `--`, so shell metacharacters remain literal.
    fn isSafePath(path: []const u8) bool {
        if (path.len == 0 or path.len > max_path) return false;
        if (path[0] == '/' or path[0] == '\\') return false;
        if (path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') return false;

        var segment_start: usize = 0;
        var i: usize = 0;
        while (i <= path.len) : (i += 1) {
            if (i < path.len) {
                const byte = path[i];
                if (byte < 0x20 or byte == 0x7f) return false;
                if (byte != '/' and byte != '\\') continue;
            }

            const segment = path[segment_start..i];
            if (segment.len == 0 or
                std.mem.eql(u8, segment, ".") or
                std.mem.eql(u8, segment, "..") or
                std.ascii.eqlIgnoreCase(segment, ".git"))
            {
                return false;
            }
            segment_start = i + 1;
        }
        return true;
    }

    fn isTrackedPath(io: std.Io, cwd: []const u8, path: []const u8) bool {
        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();
        const result = std.process.run(gpa, io, .{
            .argv = &.{ "git", "ls-files", "--error-unmatch", "--", path },
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(max_path + 1),
            .stderr_limit = .limited(1024),
        }) catch return false;
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        return switch (result.term) {
            .exited => |code| code == 0,
            else => false,
        };
    }

    /// Stage one repository-relative path without invoking a shell.
    pub fn stagePath(self: *GitBuffers, io: std.Io, cwd: []const u8, path: []const u8) []const u8 {
        if (cwd.len == 0) return "no workspace";
        if (!isSafePath(path)) return "unsafe path";
        if (!isGitRoot(io, cwd)) return "not a git root";
        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();
        const result = std.process.run(gpa, io, .{
            .argv = &.{ "git", "add", "--", path },
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(1024),
            .stderr_limit = .limited(1024),
        }) catch return "stage failed";
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        switch (result.term) {
            .exited => |code| {
                if (code == 0) {
                    self.refresh(io, cwd);
                    return "staged";
                }
            },
            else => {},
        }
        return "stage failed";
    }

    /// Unstage one path while preserving its working-tree contents.
    pub fn unstagePath(self: *GitBuffers, io: std.Io, cwd: []const u8, path: []const u8) []const u8 {
        if (cwd.len == 0) return "no workspace";
        if (!isSafePath(path)) return "unsafe path";
        if (!isGitRoot(io, cwd)) return "not a git root";
        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();
        const result = std.process.run(gpa, io, .{
            .argv = &.{ "git", "reset", "HEAD", "--", path },
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(1024),
            .stderr_limit = .limited(1024),
        }) catch return "unstage failed";
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        switch (result.term) {
            .exited => |code| {
                if (code == 0) {
                    self.refresh(io, cwd);
                    return "unstaged";
                }
            },
            else => {},
        }
        return "unstage failed";
    }

    /// Restore one tracked path from the index. Untracked paths are never removed or overwritten.
    pub fn restorePath(self: *GitBuffers, io: std.Io, cwd: []const u8, path: []const u8) []const u8 {
        if (cwd.len == 0) return "no workspace";
        if (!isSafePath(path)) return "unsafe path";
        if (!isGitRoot(io, cwd)) return "not a git root";
        if (!isTrackedPath(io, cwd, path)) return "refusing untracked path";
        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();
        const result = std.process.run(gpa, io, .{
            .argv = &.{ "git", "checkout", "--", path },
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(1024),
            .stderr_limit = .limited(1024),
        }) catch return "restore failed";
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        switch (result.term) {
            .exited => |code| {
                if (code == 0) {
                    self.refresh(io, cwd);
                    return "restored";
                }
            },
            else => {},
        }
        return "restore failed";
    }

    /// `git add -A` in the workspace. Returns a short status string.
    pub fn stageAll(self: *GitBuffers, io: std.Io, cwd: []const u8) []const u8 {
        if (cwd.len == 0) return "no workspace";
        if (!isGitRoot(io, cwd)) return "not a git root";
        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();
        const result = std.process.run(gpa, io, .{
            .argv = &.{ "git", "add", "-A" },
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(1024),
            .stderr_limit = .limited(1024),
        }) catch return "stage failed";
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        switch (result.term) {
            .exited => |code| {
                if (code == 0) {
                    self.refresh(io, cwd);
                    return "staged all";
                }
            },
            else => {},
        }
        return "stage failed";
    }

    /// `git commit -m <message>` then refresh. Returns a short status string.
    pub fn commitWithMessage(self: *GitBuffers, io: std.Io, cwd: []const u8, message: []const u8) []const u8 {
        if (cwd.len == 0) return "no workspace";
        if (message.len == 0) return "empty message";
        if (!isGitRoot(io, cwd)) return "not a git root";
        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();
        const result = std.process.run(gpa, io, .{
            .argv = &.{ "git", "commit", "-m", message },
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(4096),
            .stderr_limit = .limited(4096),
        }) catch return "commit failed";
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        switch (result.term) {
            .exited => |code| {
                if (code == 0) {
                    self.refresh(io, cwd);
                    return "committed";
                }
            },
            else => {},
        }
        // Nothing to commit is common — surface a clearer label.
        if (std.mem.indexOf(u8, result.stderr, "nothing to commit") != null) return "nothing to commit";
        return "commit failed";
    }

    /// `git reset HEAD` — unstage the index without touching the working tree.
    pub fn unstageAll(self: *GitBuffers, io: std.Io, cwd: []const u8) []const u8 {
        if (cwd.len == 0) return "no workspace";
        if (!isGitRoot(io, cwd)) return "not a git root";
        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();
        const result = std.process.run(gpa, io, .{
            .argv = &.{ "git", "reset", "HEAD" },
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(4096),
            .stderr_limit = .limited(4096),
        }) catch return "unstage failed";
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        switch (result.term) {
            .exited => |code| {
                // reset exits 0 even when nothing was staged.
                if (code == 0) {
                    self.refresh(io, cwd);
                    return "unstaged all";
                }
            },
            else => {},
        }
        return "unstage failed";
    }

    /// Discard tracked working-tree changes (`git checkout -- .`). Soft-confirm in UI.
    pub fn discardWorkingTree(self: *GitBuffers, io: std.Io, cwd: []const u8) []const u8 {
        if (cwd.len == 0) return "no workspace";
        if (!isGitRoot(io, cwd)) return "not a git root";
        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();
        const result = std.process.run(gpa, io, .{
            .argv = &.{ "git", "checkout", "--", "." },
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(4096),
            .stderr_limit = .limited(4096),
        }) catch return "discard failed";
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        switch (result.term) {
            .exited => |code| {
                if (code == 0) {
                    self.refresh(io, cwd);
                    return "discarded changes";
                }
            },
            else => {},
        }
        return "discard failed";
    }

    pub fn refresh(self: *GitBuffers, io: std.Io, cwd: []const u8) void {
        self.clear();
        if (cwd.len == 0) {
            self.summary = "no workspace";
            return;
        }
        if (!isGitRoot(io, cwd)) {
            self.summary = "not a git root";
            return;
        }
        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();

        // Branch
        if (std.process.run(gpa, io, .{
            .argv = &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" },
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(256),
            .stderr_limit = .limited(256),
        })) |branch_result| {
            defer {
                gpa.free(branch_result.stdout);
                gpa.free(branch_result.stderr);
            }
            switch (branch_result.term) {
                .exited => |code| {
                    if (code == 0) {
                        const trimmed = std.mem.trim(u8, branch_result.stdout, " \t\r\n");
                        const n = @min(trimmed.len, self.branch_buf.len);
                        @memcpy(self.branch_buf[0..n], trimmed[0..n]);
                        self.branch_len = n;
                        self.available = true;
                    }
                },
                else => {},
            }
        } else |_| {
            self.summary = "git unavailable";
            return;
        }

        const status_result = std.process.run(gpa, io, .{
            .argv = &.{ "git", "status", "--porcelain=v1", "-z", "-uall" },
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(64 * 1024),
            .stderr_limit = .limited(1024),
        }) catch {
            self.summary = "git status failed";
            return;
        };
        defer {
            gpa.free(status_result.stdout);
            gpa.free(status_result.stderr);
        }
        switch (status_result.term) {
            .exited => |code| {
                if (code != 0) {
                    self.summary = "not a git repo";
                    self.available = false;
                    return;
                }
            },
            else => {
                self.summary = "not a git repo";
                self.available = false;
                return;
            },
        }
        self.parsePorcelainZ(status_result.stdout);
        if (self.entry_count == 0) {
            self.summary = "clean";
        } else {
            self.summary = "changes";
        }
        self.available = true;
    }

    fn parsePorcelain(self: *GitBuffers, data: []const u8) void {
        var start: usize = 0;
        var i: usize = 0;
        while (i <= data.len and self.entry_count < max_entries) : (i += 1) {
            if (i == data.len or data[i] == '\n') {
                const line = data[start..i];
                if (line.len >= 4) {
                    const st = line[0..2];
                    var path = std.mem.trim(u8, line[3..], " \t\r");
                    // Handle rename "old -> new"
                    if (std.mem.indexOf(u8, path, " -> ")) |arrow| {
                        path = path[arrow + 4 ..];
                    }
                    self.pushEntry(st, path);
                }
                start = i + 1;
            }
        }
    }

    fn parsePorcelainZ(self: *GitBuffers, data: []const u8) void {
        var start: usize = 0;
        while (start + 3 <= data.len and self.entry_count < max_entries) {
            const terminator = std.mem.indexOfScalarPos(u8, data, start + 3, 0) orelse break;
            const status = data[start .. start + 2];
            self.pushEntry(status, data[start + 3 .. terminator]);
            start = terminator + 1;

            // In `-z` format a rename/copy stores the destination first and the source
            // as a second NUL-delimited field. The panel operates on the destination.
            if (status[0] == 'R' or status[0] == 'C' or status[1] == 'R' or status[1] == 'C') {
                const source_terminator = std.mem.indexOfScalarPos(u8, data, start, 0) orelse break;
                start = source_terminator + 1;
            }
        }
    }

    fn pushEntry(self: *GitBuffers, status: []const u8, path: []const u8) void {
        const idx = self.entry_count;
        const slen = @min(status.len, self.status_pool[idx].len);
        @memcpy(self.status_pool[idx][0..slen], status[0..slen]);
        self.status_lens[idx] = slen;
        const plen = @min(path.len, self.path_pool[idx].len);
        @memcpy(self.path_pool[idx][0..plen], path[0..plen]);
        self.path_lens[idx] = plen;
        self.entries[idx] = .{
            .id = idx + 1,
            .status = self.status_pool[idx][0..slen],
            .path = self.path_pool[idx][0..plen],
        };
        self.entry_count += 1;
    }
};

test "git buffers parse porcelain lines" {
    var g: GitBuffers = .{};
    g.parsePorcelain(" M src/app.tsx\n?? new.ts\n");
    try std.testing.expect(g.entry_count == 2);
    try std.testing.expectEqualStrings(" M", g.entries[0].status);
    try std.testing.expectEqualStrings("src/app.tsx", g.entries[0].path);
}

test "git buffers parse exact nul-delimited paths and rename destination" {
    var g: GitBuffers = .{};
    g.parsePorcelainZ("?? space ;$' file.txt\x00R  new name.txt\x00old name.txt\x00");
    try std.testing.expectEqual(@as(u32, 2), g.entry_count);
    try std.testing.expectEqualStrings("space ;$' file.txt", g.entries[0].path);
    try std.testing.expectEqualStrings("R ", g.entries[1].status);
    try std.testing.expectEqualStrings("new name.txt", g.entries[1].path);
}

fn runTestGit(cwd: []const u8, argv: []const []const u8) !void {
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
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

fn initTestRepo(tmp: *std.testing.TmpDir, path_buf: []u8) ![]const u8 {
    const cwd = try std.fmt.bufPrint(path_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try runTestGit(cwd, &.{ "git", "init", "-q" });
    try runTestGit(cwd, &.{ "git", "config", "user.email", "scm-test@example.invalid" });
    try runTestGit(cwd, &.{ "git", "config", "user.name", "SCM Test" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "tracked.txt", .data = "original\n" });
    try runTestGit(cwd, &.{ "git", "add", "--", "tracked.txt" });
    try runTestGit(cwd, &.{ "git", "commit", "-q", "-m", "initial" });
    return cwd;
}

test "per-path stage and unstage preserve literal path contents" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [128]u8 = undefined;
    const cwd = try initTestRepo(&tmp, &path_buf);
    const literal_path = "space ;$' file.txt";
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = literal_path, .data = "literal\n" });

    var g: GitBuffers = .{};
    try std.testing.expectEqualStrings("staged", g.stagePath(std.testing.io, cwd, literal_path));
    try std.testing.expectEqual(@as(u32, 1), g.entry_count);
    try std.testing.expectEqualStrings("A ", g.entries[0].status);
    try std.testing.expectEqualStrings(literal_path, g.entries[0].path);
    try std.testing.expectEqualStrings("unstaged", g.unstagePath(std.testing.io, cwd, literal_path));
    try std.testing.expectEqual(@as(u32, 1), g.entry_count);
    try std.testing.expectEqualStrings("??", g.entries[0].status);
    try std.testing.expectEqualStrings(literal_path, g.entries[0].path);

    var out: [32]u8 = undefined;
    const contents = try tmp.dir.readFile(std.testing.io, literal_path, &out);
    try std.testing.expectEqualStrings("literal\n", contents);
}

test "restore path restores tracked file and refuses untracked file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [128]u8 = undefined;
    const cwd = try initTestRepo(&tmp, &path_buf);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "tracked.txt", .data = "modified\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "untracked.txt", .data = "keep\n" });

    var g: GitBuffers = .{};
    try std.testing.expectEqualStrings("restored", g.restorePath(std.testing.io, cwd, "tracked.txt"));
    try std.testing.expectEqualStrings("refusing untracked path", g.restorePath(std.testing.io, cwd, "untracked.txt"));

    var out: [32]u8 = undefined;
    const tracked = try tmp.dir.readFile(std.testing.io, "tracked.txt", &out);
    try std.testing.expectEqualStrings("original\n", tracked);
    const untracked = try tmp.dir.readFile(std.testing.io, "untracked.txt", &out);
    try std.testing.expectEqualStrings("keep\n", untracked);
}

test "per-path operations reject absolute traversal and git metadata paths" {
    var g: GitBuffers = .{};
    try std.testing.expectEqualStrings("unsafe path", g.stagePath(std.testing.io, "/unused", "../outside.txt"));
    try std.testing.expectEqualStrings("unsafe path", g.unstagePath(std.testing.io, "/unused", "/absolute.txt"));
    try std.testing.expectEqualStrings("unsafe path", g.restorePath(std.testing.io, "/unused", ".git/config"));
    try std.testing.expectEqualStrings("unsafe path", g.stagePath(std.testing.io, "/unused", "dir\\..\\outside.txt"));
}
