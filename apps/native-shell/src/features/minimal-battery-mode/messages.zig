//! Messages for feature.minimal-battery-mode.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
