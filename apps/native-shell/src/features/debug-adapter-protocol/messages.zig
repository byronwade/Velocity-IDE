//! Messages for feature.debug-adapter-protocol.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
