//! Messages for feature.debug-core.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
