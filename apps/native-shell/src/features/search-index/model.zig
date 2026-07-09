//! Search Index feature model stub.
//! Status: stub. Mode: dev. Startup allowed: False.

pub const feature_id = "feature.search-index";
pub const mode = "dev";
pub const memory_budget_mb: u32 = 64;
pub const max_processes: u32 = 1;
pub const startup_allowed = false;

pub const Model = struct {
    enabled: bool = true,
    loaded: bool = false,
    activation_reason: []const u8 = "none",
};
