//! Messages for feature.memory-pressure-mode.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
