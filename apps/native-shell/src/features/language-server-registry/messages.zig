//! Messages for feature.language-server-registry.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
