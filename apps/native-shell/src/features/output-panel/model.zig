//! Output Panel lazy feature state.
//! Status: working. Mode: dev. Startup allowed: False.

pub const feature_id = "feature.output-panel";
pub const mode = "dev";
pub const memory_budget_mb: u32 = 16;
pub const max_processes: u32 = 0;
pub const startup_allowed = false;

pub const Model = struct {
    enabled: bool = true,
    loaded: bool = false,
    activation_reason: []const u8 = "none",
};
