//! Messages for feature.auto-save.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
