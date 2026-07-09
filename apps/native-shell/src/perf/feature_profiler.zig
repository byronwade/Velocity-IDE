//! Honest feature registry totals.

const feature_registry = @import("../core/feature_registry.zig");

pub const Sample = struct {
    registered: u32,
    enabled: u32,
    loaded: u32,
};

pub fn sample() Sample {
    return .{
        .registered = feature_registry.registered_count,
        .enabled = feature_registry.countEnabled(&feature_registry.catalog),
        .loaded = feature_registry.countLoaded(&feature_registry.catalog),
    };
}
