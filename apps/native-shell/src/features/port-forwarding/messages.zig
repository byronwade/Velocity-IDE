//! Messages for feature.port-forwarding.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
