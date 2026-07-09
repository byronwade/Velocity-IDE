//! Messages for feature.status-bar.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
