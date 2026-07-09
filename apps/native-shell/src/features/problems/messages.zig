//! Messages for feature.problems.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
