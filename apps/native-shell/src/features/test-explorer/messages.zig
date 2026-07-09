//! Messages for feature.test-explorer.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
