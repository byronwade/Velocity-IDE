//! Messages for feature.suspend-inactive-language-servers.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
