//! Messages for feature.completion-registry.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
