//! Messages for feature.formatting.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
