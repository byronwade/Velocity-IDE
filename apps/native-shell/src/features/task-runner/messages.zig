//! Messages for feature.task-runner.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
