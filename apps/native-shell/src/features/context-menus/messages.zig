//! Messages for feature.context-menus.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
