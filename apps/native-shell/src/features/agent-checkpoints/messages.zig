//! Messages for feature.agent-checkpoints.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
