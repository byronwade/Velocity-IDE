//! Messages for feature.terminal-splits.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
