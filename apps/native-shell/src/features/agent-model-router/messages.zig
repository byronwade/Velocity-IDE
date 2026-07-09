//! Messages for feature.agent-model-router.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
