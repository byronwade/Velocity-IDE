//! Messages for feature.multi-cursor.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
