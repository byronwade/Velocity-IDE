//! Messages for feature.agent-tool-registry.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
