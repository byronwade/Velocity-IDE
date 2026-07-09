//! Messages for feature.debug-console.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
