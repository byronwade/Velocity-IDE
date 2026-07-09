//! Messages for feature.plugin-sandbox.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
