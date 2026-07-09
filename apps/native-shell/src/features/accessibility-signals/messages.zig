//! Messages for feature.accessibility-signals.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
