//! Messages for feature.terminal-links.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
