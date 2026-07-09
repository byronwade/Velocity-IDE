//! Messages for feature.language-status.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
