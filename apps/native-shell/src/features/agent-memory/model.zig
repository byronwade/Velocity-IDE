//! Agent Memory feature model stub.
//! Status: stub. Mode: agent. Startup allowed: False.

pub const feature_id = "feature.agent-memory";
pub const mode = "agent";
pub const memory_budget_mb: u32 = 32;
pub const max_processes: u32 = 0;
pub const startup_allowed = false;

pub const Model = struct {
    enabled: bool = false,
    loaded: bool = false,
    activation_reason: []const u8 = "none",
};
