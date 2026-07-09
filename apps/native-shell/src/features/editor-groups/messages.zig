//! Messages for feature.editor-groups.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
