//! Messages for feature.hover-docs.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
