//! Messages for feature.plugin-activation.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
