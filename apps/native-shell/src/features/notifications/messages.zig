//! Messages for feature.notifications.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
