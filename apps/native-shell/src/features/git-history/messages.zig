//! Messages for feature.git-history.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
