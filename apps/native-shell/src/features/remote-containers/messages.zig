//! Messages for feature.remote-containers.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
