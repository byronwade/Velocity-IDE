//! Messages for feature.kill-all-workspace-processes.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
