//! Codebase Index Health View feature model stub.
//! Status: stub. Mode: agent. Startup allowed: False.

pub const feature_id = "feature.codebase-index-health";
pub const mode = "agent";
pub const memory_budget_mb: u32 = 8;
pub const max_processes: u32 = 0;
pub const startup_allowed = false;

pub const Model = struct {
    enabled: bool = true,
    loaded: bool = false,
    activation_reason: []const u8 = "none",
};
