//! Messages for feature.agent-worktree-manager.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
