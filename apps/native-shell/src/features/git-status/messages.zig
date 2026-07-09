//! Messages for feature.git-status.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
