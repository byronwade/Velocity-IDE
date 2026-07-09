//! Messages for feature.parallel-agent-task-board.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
