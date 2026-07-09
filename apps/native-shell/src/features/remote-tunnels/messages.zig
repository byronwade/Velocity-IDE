//! Messages for feature.remote-tunnels.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
