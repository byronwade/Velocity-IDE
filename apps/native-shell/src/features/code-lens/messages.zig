//! Messages for feature.code-lens.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
