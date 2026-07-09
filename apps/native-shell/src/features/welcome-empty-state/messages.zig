//! Messages for feature.welcome-empty-state.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
