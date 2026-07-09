//! Messages for feature.instant-safe-mode.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
