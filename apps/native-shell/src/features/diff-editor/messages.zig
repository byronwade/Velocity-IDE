//! Messages for feature.diff-editor.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
