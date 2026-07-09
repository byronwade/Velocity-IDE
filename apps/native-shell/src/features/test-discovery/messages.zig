//! Messages for feature.test-discovery.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
