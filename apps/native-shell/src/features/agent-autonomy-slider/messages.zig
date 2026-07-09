//! Messages for feature.agent-autonomy-slider.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
