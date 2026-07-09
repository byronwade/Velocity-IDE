//! Messages for feature.multi-root-workspaces.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
