//! Messages for feature.workspace-trust-plus.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
