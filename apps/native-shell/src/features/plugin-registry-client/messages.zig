//! Messages for feature.plugin-registry-client.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
