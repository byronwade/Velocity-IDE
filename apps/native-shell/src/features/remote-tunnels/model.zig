//! Remote Tunnels feature model stub.
//! Status: stub. Mode: remote. Startup allowed: False.

pub const feature_id = "feature.remote-tunnels";
pub const mode = "remote";
pub const memory_budget_mb: u32 = 24;
pub const max_processes: u32 = 0;
pub const startup_allowed = false;

pub const Model = struct {
    enabled: bool = false,
    loaded: bool = false,
    activation_reason: []const u8 = "none",
};
