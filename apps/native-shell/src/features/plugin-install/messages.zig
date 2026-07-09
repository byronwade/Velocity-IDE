//! Messages for feature.plugin-install.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
