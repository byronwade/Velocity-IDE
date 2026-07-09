//! Messages for feature.plugin-performance-score.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
