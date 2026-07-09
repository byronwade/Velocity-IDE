//! Messages for feature.syntax-highlighting.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
