//! Legacy Extension Host feature model stub.
//! Status: stub. Mode: legacy. Startup allowed: False.

pub const feature_id = "feature.legacy-extension-host";
pub const mode = "legacy";
pub const memory_budget_mb: u32 = 128;
pub const max_processes: u32 = 1;
pub const startup_allowed = false;

pub const Model = struct {
    enabled: bool = false,
    loaded: bool = false,
    activation_reason: []const u8 = "none",
};
