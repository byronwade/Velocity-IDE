//! Messages for feature.agent-apply.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
