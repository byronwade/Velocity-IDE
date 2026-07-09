//! Messages for feature.call-stack.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
