//! Terminal feature model scaffold.
//! Status: prototype. Pipe runner works; interactive PTY is blocked by SDK.

pub const feature_id = "feature.terminal";
pub const mode = "core";
pub const memory_budget_mb: u32 = 32;
pub const max_processes: u32 = 1;
pub const startup_allowed = false;

pub const Model = struct {
    enabled: bool = true,
    loaded: bool = false,
    activation_reason: []const u8 = "none",
};
