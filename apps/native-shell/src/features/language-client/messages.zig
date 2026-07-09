//! Messages for feature.language-client.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
