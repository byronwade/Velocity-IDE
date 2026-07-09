//! Messages for feature.test-output.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
