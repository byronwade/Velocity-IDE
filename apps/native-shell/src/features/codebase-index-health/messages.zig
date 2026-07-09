//! Messages for feature.codebase-index-health.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
