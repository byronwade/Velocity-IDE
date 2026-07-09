//! Messages for feature.search-editor.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
