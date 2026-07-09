//! Messages for feature.file-encoding.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
