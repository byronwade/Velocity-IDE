//! Messages for feature.accessibility-core.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
