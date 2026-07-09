//! Messages for feature.file-watchers.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
