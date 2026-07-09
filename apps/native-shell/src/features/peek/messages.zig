//! Messages for feature.peek.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
