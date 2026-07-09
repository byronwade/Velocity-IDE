//! Messages for feature.debug-configurations.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
