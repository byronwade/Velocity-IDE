//! Messages for feature.freeze-background-terminals.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
