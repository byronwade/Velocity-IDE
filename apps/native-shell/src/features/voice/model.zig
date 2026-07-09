//! Voice feature model stub.
//! Status: stub. Mode: heavy. Startup allowed: False.

pub const feature_id = "feature.voice";
pub const mode = "heavy";
pub const memory_budget_mb: u32 = 32;
pub const max_processes: u32 = 0;
pub const startup_allowed = false;

pub const Model = struct {
    enabled: bool = false,
    loaded: bool = false,
    activation_reason: []const u8 = "none",
};
