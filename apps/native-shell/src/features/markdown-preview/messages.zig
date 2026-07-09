//! Messages for feature.markdown-preview.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
