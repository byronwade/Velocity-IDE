//! Messages for feature.no-extensions-mode.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
