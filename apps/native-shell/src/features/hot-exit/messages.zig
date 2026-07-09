//! Messages for feature.hot-exit.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
