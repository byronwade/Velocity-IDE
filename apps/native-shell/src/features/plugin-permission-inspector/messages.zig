//! Messages for feature.plugin-permission-inspector.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
