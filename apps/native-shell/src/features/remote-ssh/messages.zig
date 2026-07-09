//! Messages for feature.remote-ssh.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
