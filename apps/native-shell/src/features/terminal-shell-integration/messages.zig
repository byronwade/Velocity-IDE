//! Messages for feature.terminal-shell-integration.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
