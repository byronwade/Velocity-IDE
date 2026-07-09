//! Messages for feature.plugin-host-process.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
