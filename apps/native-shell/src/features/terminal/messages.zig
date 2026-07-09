//! Messages for feature.terminal.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
