//! Messages for feature.language-registry.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
