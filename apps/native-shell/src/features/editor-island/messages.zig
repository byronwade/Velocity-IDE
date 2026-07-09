//! Messages for feature.editor-island.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
