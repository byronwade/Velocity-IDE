//! Messages for feature.git-merge-conflicts.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
