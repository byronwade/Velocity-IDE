//! Lightweight git status for SCM panel (MVP).
//! Runs `git status --porcelain` via Process Governor bookkeeping + process.run.

const std = @import("std");

pub const max_entries: usize = 64;
pub const max_path: usize = 200;
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

    pub fn entriesSlice(self: *GitBuffers) []const GitEntry {
        return self.entries[0..self.entry_count];
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
    }

    pub fn refresh(self: *GitBuffers, io: std.Io, cwd: []const u8) void {
        self.clear();
        if (cwd.len == 0) {
            self.summary = "no workspace";
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
            .argv = &.{ "git", "status", "--porcelain", "-uall" },
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
        self.parsePorcelain(status_result.stdout);
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
