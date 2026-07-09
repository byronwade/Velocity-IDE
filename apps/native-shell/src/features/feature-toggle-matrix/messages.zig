//! Messages for feature.feature-toggle-matrix.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
