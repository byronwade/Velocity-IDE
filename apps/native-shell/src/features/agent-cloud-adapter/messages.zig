//! Messages for feature.agent-cloud-adapter.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
