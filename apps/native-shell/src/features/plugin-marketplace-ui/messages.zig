//! Messages for feature.plugin-marketplace-ui.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
