//! Messages for feature.file-decorations.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
