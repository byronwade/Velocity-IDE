//! Messages for feature.crash-leak-reporter.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
