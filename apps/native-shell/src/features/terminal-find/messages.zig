//! Messages for feature.terminal-find.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
