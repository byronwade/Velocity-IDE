//! Process event log stub (local only, no telemetry).
pub const Entry = struct { ms: u64 = 0, kind: []const u8 = "", detail: []const u8 = "" };
