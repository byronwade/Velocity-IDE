//! Messages for feature.quick-open.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
