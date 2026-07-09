//! Messages for feature.agent-local-adapter.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
