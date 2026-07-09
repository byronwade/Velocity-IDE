//! Editor Island feature model stub.
//! Status: stub. Mode: core. Startup allowed: False.

pub const feature_id = "feature.editor-island";
pub const mode = "core";
pub const memory_budget_mb: u32 = 32;
pub const max_processes: u32 = 0;
pub const startup_allowed = false;

pub const Model = struct {
    enabled: bool = true,
    loaded: bool = false,
    activation_reason: []const u8 = "none",
};
