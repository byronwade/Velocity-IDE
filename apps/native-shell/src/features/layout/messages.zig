//! Messages for feature.layout.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
