//! Messages for feature.performance-hud.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
