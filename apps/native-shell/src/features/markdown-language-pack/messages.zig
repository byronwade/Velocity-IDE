//! Messages for feature.markdown-language-pack.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
