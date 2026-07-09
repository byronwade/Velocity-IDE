//! Messages for feature.panel.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
