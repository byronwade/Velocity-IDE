//! Messages for feature.workspace-process-sandbox.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
