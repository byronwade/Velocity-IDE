//! Messages for feature.agent-review.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
