//! Messages for feature.git-branches.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
