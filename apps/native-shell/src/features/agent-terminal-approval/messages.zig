//! Messages for feature.agent-terminal-approval.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
