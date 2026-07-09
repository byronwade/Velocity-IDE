//! Messages for feature.plugin-permissions.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
