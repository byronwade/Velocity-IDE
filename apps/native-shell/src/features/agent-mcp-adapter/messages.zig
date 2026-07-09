//! Messages for feature.agent-mcp-adapter.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
