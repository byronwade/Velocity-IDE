//! Messages for feature.code-actions.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
