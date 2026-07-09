//! Messages for feature.agent-memory.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
