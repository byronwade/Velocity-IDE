//! Messages for feature.json-language-pack.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
