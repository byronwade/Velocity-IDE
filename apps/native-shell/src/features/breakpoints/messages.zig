//! Messages for feature.breakpoints.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
