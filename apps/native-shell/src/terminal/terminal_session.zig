//! Terminal session — pipe-based command runner (MVP; not a full PTY).
//! Spawns only after Process Governor bookkeeping; uses std.process.run.

const std = @import("std");

pub const max_lines: usize = 200;
pub const max_line_bytes: usize = 240;
pub const max_command: usize = 160;
pub const max_output_collect: usize = 32 * 1024;

pub const TerminalBuffers = struct {
    line_pool: [max_lines][max_line_bytes]u8 = undefined,
    line_lens: [max_lines]usize = [_]usize{0} ** max_lines,
    lines: [max_lines][]const u8 = [_][]const u8{""} ** max_lines,
    line_count: u32 = 0,
    status: []const u8 = "idle",
    last_exit: i32 = 0,
    running: bool = false,

    pub fn linesSlice(self: *TerminalBuffers) []const []const u8 {
        return self.lines[0..self.line_count];
    }

    pub fn clear(self: *TerminalBuffers) void {
        self.line_count = 0;
        self.status = "idle";
        self.last_exit = 0;
        self.running = false;
    }

    pub fn pushLine(self: *TerminalBuffers, text: []const u8) void {
        if (self.line_count >= max_lines) {
            var i: u32 = 0;
            while (i + 1 < self.line_count) : (i += 1) {
                const len = self.line_lens[i + 1];
                @memcpy(self.line_pool[i][0..len], self.line_pool[i + 1][0..len]);
                self.line_lens[i] = len;
                self.lines[i] = self.line_pool[i][0..len];
            }
            self.line_count -= 1;
        }
        const idx = self.line_count;
        const n = @min(text.len, max_line_bytes);
        @memcpy(self.line_pool[idx][0..n], text[0..n]);
        self.line_lens[idx] = n;
        self.lines[idx] = self.line_pool[idx][0..n];
        self.line_count += 1;
    }

    pub fn pushPrompt(self: *TerminalBuffers, cmd: []const u8) void {
        var buf: [max_line_bytes]u8 = undefined;
        const prefix = "$ ";
        const take = @min(cmd.len, max_line_bytes - prefix.len);
        @memcpy(buf[0..prefix.len], prefix);
        @memcpy(buf[prefix.len..][0..take], cmd[0..take]);
        self.pushLine(buf[0 .. prefix.len + take]);
    }

    /// Run a shell command via `/bin/sh -c` and capture stdout/stderr lines.
    pub fn runCommand(self: *TerminalBuffers, io: std.Io, cwd: []const u8, command: []const u8) void {
        if (command.len == 0) return;
        self.pushPrompt(command);
        self.running = true;
        self.status = "running";

        var gpa_state: std.heap.DebugAllocator(.{}) = .init;
        defer _ = gpa_state.deinit();
        const gpa = gpa_state.allocator();

        const result = std.process.run(gpa, io, .{
            .argv = &.{ "/bin/sh", "-c", command },
            .cwd = if (cwd.len > 0) .{ .path = cwd } else .inherit,
            .stdout_limit = .limited(max_output_collect),
            .stderr_limit = .limited(max_output_collect),
        }) catch {
            self.pushLine("error: spawn failed");
            self.running = false;
            self.status = "failed";
            return;
        };
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }

        self.appendOutput(result.stdout);
        if (result.stderr.len > 0) self.appendOutput(result.stderr);

        self.last_exit = switch (result.term) {
            .exited => |code| @intCast(code),
            else => 1,
        };
        self.running = false;
        self.status = if (self.last_exit == 0) "ok" else "exit";
        var exit_buf: [32]u8 = undefined;
        const exit_msg = std.fmt.bufPrint(&exit_buf, "[exit {d}]", .{self.last_exit}) catch "[exit]";
        self.pushLine(exit_msg);
    }

    fn appendOutput(self: *TerminalBuffers, data: []const u8) void {
        var start: usize = 0;
        var i: usize = 0;
        while (i <= data.len) : (i += 1) {
            if (i == data.len or data[i] == '\n') {
                if (i > start) self.pushLine(data[start..i]);
                start = i + 1;
            }
        }
    }
};

test "terminal ring pushes lines" {
    var t: TerminalBuffers = .{};
    t.pushLine("hello");
    t.pushLine("world");
    try std.testing.expect(t.line_count == 2);
    try std.testing.expectEqualStrings("hello", t.lines[0]);
}

test "run echo command" {
    var t: TerminalBuffers = .{};
    t.runCommand(std.testing.io, "", "echo velocity-mvp");
    try std.testing.expect(t.line_count >= 2);
    var found = false;
    for (t.lines[0..t.line_count]) |line| {
        if (std.mem.indexOf(u8, line, "velocity-mvp") != null) found = true;
    }
    try std.testing.expect(found);
    try std.testing.expect(t.last_exit == 0);
}
