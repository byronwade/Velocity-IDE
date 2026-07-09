//! Messages for feature.dialogs.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
