//! Messages for feature.js-ts-language-pack.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
