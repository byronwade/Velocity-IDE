//! Messages for feature.agent-permissions.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
