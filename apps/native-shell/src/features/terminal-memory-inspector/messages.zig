//! Messages for feature.terminal-memory-inspector.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
