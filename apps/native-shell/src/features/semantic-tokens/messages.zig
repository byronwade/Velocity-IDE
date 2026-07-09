//! Messages for feature.semantic-tokens.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
