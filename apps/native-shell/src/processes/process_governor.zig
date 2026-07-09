//! Process Governor — sole spawn path for Velocity child processes.
//! Features must not spawn directly.

const std = @import("std");

pub const KillPolicy = enum { on_feature_disable, on_workspace_close, on_owner_close, never };
pub const IdlePolicy = enum { none, suspend_idle, kill };
pub const TrustPolicy = enum { require_workspace_trust, allow_untrusted };

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
        // Scaffold: record only — no real OS spawn yet.
        if (self.count >= max_tracked) return error.ProcessBudgetExceeded;
        const id = self.next_id;
        self.next_id += 1;
        const idx = self.count;
        self.count += 1;
        self.records[idx] = .{
            .id = id,
            .parent_feature = feature,
            .command = command,
            .alive = true,
        };
        return id;
    }

    pub fn kill(self: *Governor, id: u32) void {
        for (&self.records) |*r| {
            if (r.id == id and r.alive) {
                r.alive = false;
                return;
            }
        }
    }

    pub fn killFeature(self: *Governor, feature: []const u8) void {
        for (&self.records) |*r| {
            if (r.alive and std.mem.eql(u8, r.parent_feature, feature)) {
                r.alive = false;
            }
        }
    }

    pub fn aliveCount(self: *const Governor) u32 {
        var n: u32 = 0;
        for (self.records[0..self.count]) |r| if (r.alive) {
            n += 1;
        };
        return n;
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
