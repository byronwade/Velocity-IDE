//! Messages for feature.plugin-update.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
