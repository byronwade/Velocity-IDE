//! Messages for feature.git-stage-commit.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
