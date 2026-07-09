//! Messages for feature.hover.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
