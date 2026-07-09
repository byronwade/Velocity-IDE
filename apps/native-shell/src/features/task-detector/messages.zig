//! Messages for feature.task-detector.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
