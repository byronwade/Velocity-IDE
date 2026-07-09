//! Accessibility Core feature model stub.
//! Status: stub. Mode: core. Startup allowed: True.

pub const feature_id = "feature.accessibility-core";
pub const mode = "core";
pub const memory_budget_mb: u32 = 4;
pub const max_processes: u32 = 0;
pub const startup_allowed = true;

pub const Model = struct {
    enabled: bool = true,
    loaded: bool = false,
    activation_reason: []const u8 = "none",
};
