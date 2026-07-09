//! Messages for feature.semantic-token-registry.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
