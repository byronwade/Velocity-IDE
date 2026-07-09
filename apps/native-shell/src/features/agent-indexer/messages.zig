//! Messages for feature.agent-indexer.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
