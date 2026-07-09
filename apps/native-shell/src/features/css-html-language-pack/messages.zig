//! Messages for feature.css-html-language-pack.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
