//! Messages for feature.git-diff.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
