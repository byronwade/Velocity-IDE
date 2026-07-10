//! Process Governor — sole spawn path for Velocity child processes.
//! Features must not spawn directly.

const std = @import("std");

pub const KillPolicy = enum { on_feature_disable, on_workspace_close, on_owner_close, never };
pub const IdlePolicy = enum { none, suspend_idle, kill };
pub const TrustPolicy = enum { require_workspace_trust, allow_untrusted };
pub const ProcessStatus = enum {
    running,
    exited,
    cancelled,
    rejected,
    signaled,
    spawn_failed,
    killed,
};

pub const Ownership = struct {
    terminal: bool = false,
    task: bool = false,
    lsp: bool = false,
    debug: bool = false,
    /// Interactive PTY session (sidecar broker); budgeted separately from
    /// the pipe runner so an open interactive shell never starves tasks.
    pty: bool = false,
};

pub const OwnershipCounts = struct {
    terminal: u32 = 0,
    task: u32 = 0,
    lsp: u32 = 0,
    debug: u32 = 0,
    pty: u32 = 0,
};

pub const ProcessRecord = struct {
    id: u32 = 0,
    os_pid: u32 = 0,
    parent_feature: []const u8 = "",
    workspace_id: []const u8 = "",
    command: []const u8 = "",
    cwd: []const u8 = "",
    start_ms: u64 = 0,
    last_activity_ms: u64 = 0,
    memory_estimate_mb: u32 = 0,
    cpu_estimate: f32 = 0,
    kill_policy: KillPolicy = .on_workspace_close,
    idle_policy: IdlePolicy = .suspend_idle,
    trust_policy: TrustPolicy = .require_workspace_trust,
    terminal_owned: bool = false,
    lsp_owned: bool = false,
    task_owned: bool = false,
    debug_owned: bool = false,
    pty_owned: bool = false,
    effect_key: u64 = 0,
    status: ProcessStatus = .running,
    exit_code: i32 = 0,
    alive: bool = false,
    leaked: bool = false,
};

pub const max_tracked: usize = 128;

pub const Governor = struct {
    records: [max_tracked]ProcessRecord = [_]ProcessRecord{.{}} ** max_tracked,
    next_id: u32 = 1,
    count: u32 = 0,
    leak_count: u32 = 0,

    pub fn spawn(self: *Governor, feature: []const u8, command: []const u8) !u32 {
        return self.spawnEffect(feature, command, 0, .{});
    }

    /// Reserve one governed process record for an SDK effect. `os_pid` stays
    /// zero because the Effects API intentionally does not expose a PID.
    pub fn spawnEffect(
        self: *Governor,
        feature: []const u8,
        command: []const u8,
        effect_key: u64,
        ownership: Ownership,
    ) !u32 {
        // Scaffold: record only — no real OS spawn yet.
        if (self.count >= max_tracked) return error.ProcessBudgetExceeded;
        if (ownership.terminal and self.aliveOwned(.terminal)) return error.TerminalProcessBudgetExceeded;
        if (ownership.task and self.aliveOwned(.task)) return error.TaskProcessBudgetExceeded;
        if (ownership.pty and self.aliveOwned(.pty)) return error.PtyProcessBudgetExceeded;
        const id = self.next_id;
        self.next_id += 1;
        const idx = self.count;
        self.count += 1;
        self.records[idx] = .{
            .id = id,
            .parent_feature = feature,
            .command = command,
            .terminal_owned = ownership.terminal,
            .task_owned = ownership.task,
            .lsp_owned = ownership.lsp,
            .debug_owned = ownership.debug,
            .pty_owned = ownership.pty,
            .effect_key = effect_key,
            .status = .running,
            .alive = true,
        };
        return id;
    }

    pub fn kill(self: *Governor, id: u32) void {
        for (&self.records) |*r| {
            if (r.id == id and r.alive) {
                r.alive = false;
                r.status = .killed;
                return;
            }
        }
    }

    pub fn killFeature(self: *Governor, feature: []const u8) void {
        for (&self.records) |*r| {
            if (r.alive and std.mem.eql(u8, r.parent_feature, feature)) {
                r.alive = false;
                r.status = .killed;
            }
        }
    }

    pub fn killAll(self: *Governor) void {
        for (self.records[0..self.count]) |*record| {
            if (record.alive) {
                record.alive = false;
                record.status = .killed;
            }
        }
    }

    pub fn closeEffect(self: *Governor, effect_key: u64, status: ProcessStatus, exit_code: i32) void {
        for (&self.records) |*record| {
            if (record.effect_key == effect_key and record.alive) {
                record.alive = false;
                record.status = status;
                record.exit_code = exit_code;
                return;
            }
        }
    }

    pub fn recordForEffect(self: *const Governor, effect_key: u64) ?*const ProcessRecord {
        var index = self.count;
        while (index > 0) {
            index -= 1;
            const record = &self.records[index];
            if (record.effect_key == effect_key) return record;
        }
        return null;
    }

    const OwnedKind = enum { terminal, task, pty };

    fn aliveOwned(self: *const Governor, kind: OwnedKind) bool {
        for (self.records[0..self.count]) |record| {
            if (!record.alive) continue;
            if (kind == .terminal and record.terminal_owned) return true;
            if (kind == .task and record.task_owned) return true;
            if (kind == .pty and record.pty_owned) return true;
        }
        return false;
    }

    pub fn aliveCount(self: *const Governor) u32 {
        var n: u32 = 0;
        for (self.records[0..self.count]) |r| if (r.alive) {
            n += 1;
        };
        return n;
    }

    pub fn aliveOwnershipCounts(self: *const Governor) OwnershipCounts {
        var counts: OwnershipCounts = .{};
        for (self.records[0..self.count]) |record| {
            if (!record.alive) continue;
            if (record.terminal_owned) counts.terminal += 1;
            if (record.task_owned) counts.task += 1;
            if (record.lsp_owned) counts.lsp += 1;
            if (record.debug_owned) counts.debug += 1;
            if (record.pty_owned) counts.pty += 1;
        }
        return counts;
    }
};

test "governor tracks spawn without OS process" {
    var g: Governor = .{};
    const id = try g.spawn("feature.terminal", "mock-pty");
    try std.testing.expect(id > 0);
    try std.testing.expect(g.aliveCount() == 1);
    g.kill(id);
    try std.testing.expect(g.aliveCount() == 0);
}

test "governor enforces terminal and task budgets and records effect outcome" {
    var g: Governor = .{};
    _ = try g.spawnEffect("feature.terminal", "sleep 1", 77, .{ .terminal = true, .task = true });
    try std.testing.expectError(
        error.TerminalProcessBudgetExceeded,
        g.spawnEffect("feature.terminal", "echo second", 78, .{ .terminal = true }),
    );
    try std.testing.expectEqual(@as(u32, 0), g.recordForEffect(77).?.os_pid);
    try std.testing.expect(g.recordForEffect(77).?.terminal_owned);
    try std.testing.expect(g.recordForEffect(77).?.task_owned);

    g.closeEffect(77, .cancelled, 130);
    const record = g.recordForEffect(77).?;
    try std.testing.expect(!record.alive);
    try std.testing.expectEqual(ProcessStatus.cancelled, record.status);
    try std.testing.expectEqual(@as(i32, 130), record.exit_code);
}

test "governor enforces the single interactive PTY budget independently" {
    var g: Governor = .{};
    _ = try g.spawnEffect("feature.terminal", "velocity-pty-broker", 90, .{ .pty = true });
    // A second interactive session is refused...
    try std.testing.expectError(
        error.PtyProcessBudgetExceeded,
        g.spawnEffect("feature.terminal", "velocity-pty-broker", 91, .{ .pty = true }),
    );
    // ...but the pipe runner / tasks are NOT starved by an open shell.
    _ = try g.spawnEffect("feature.terminal", "echo hi", 92, .{ .terminal = true, .task = true });
    try std.testing.expectEqual(@as(u32, 1), g.aliveOwnershipCounts().pty);
    g.closeEffect(90, .cancelled, -1);
    try std.testing.expectEqual(@as(u32, 0), g.aliveOwnershipCounts().pty);
    _ = try g.spawnEffect("feature.terminal", "velocity-pty-broker", 93, .{ .pty = true });
}

test "governor reports live ownership counts" {
    var g: Governor = .{};
    _ = try g.spawnEffect("feature.terminal", "echo", 1, .{ .terminal = true, .task = true });
    _ = try g.spawnEffect("feature.lsp", "server", 2, .{ .lsp = true });

    const counts = g.aliveOwnershipCounts();
    try std.testing.expectEqual(@as(u32, 1), counts.terminal);
    try std.testing.expectEqual(@as(u32, 1), counts.task);
    try std.testing.expectEqual(@as(u32, 1), counts.lsp);
    g.closeEffect(1, .exited, 0);
    try std.testing.expectEqual(@as(u32, 0), g.aliveOwnershipCounts().terminal);
}
