//! Messages for feature.diagnostic-registry.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
