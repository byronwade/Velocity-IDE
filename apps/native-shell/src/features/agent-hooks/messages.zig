//! Messages for feature.agent-hooks.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
