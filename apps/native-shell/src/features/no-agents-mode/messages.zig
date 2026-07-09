//! Messages for feature.no-agents-mode.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
