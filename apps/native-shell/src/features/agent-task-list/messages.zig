//! Messages for feature.agent-task-list.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
