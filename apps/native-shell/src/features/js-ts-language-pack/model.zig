//! JS/TS Language Pack feature model stub.
//! Status: stub. Mode: core. Startup allowed: False.

pub const feature_id = "feature.js-ts-language-pack";
pub const mode = "core";
pub const memory_budget_mb: u32 = 48;
pub const max_processes: u32 = 1;
pub const startup_allowed = false;

pub const Model = struct {
    enabled: bool = true,
    loaded: bool = false,
    activation_reason: []const u8 = "none",
};
