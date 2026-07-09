//! Messages for feature.workspace-manager.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
