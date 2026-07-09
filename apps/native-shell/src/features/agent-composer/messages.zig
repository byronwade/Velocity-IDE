//! Messages for feature.agent-composer.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
