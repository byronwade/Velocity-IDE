//! Messages for feature.file-explorer.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
