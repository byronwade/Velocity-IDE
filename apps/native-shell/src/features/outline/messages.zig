//! Messages for feature.outline.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
