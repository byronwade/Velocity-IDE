//! Messages for feature.output-panel.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
