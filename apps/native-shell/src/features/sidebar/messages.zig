//! Messages for feature.sidebar.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
