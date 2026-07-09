//! Messages for feature.problem-matchers.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
