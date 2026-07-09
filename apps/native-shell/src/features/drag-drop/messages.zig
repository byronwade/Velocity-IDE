//! Messages for feature.drag-drop.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
