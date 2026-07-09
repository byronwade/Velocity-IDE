//! Messages for feature.process-governor-ui.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
