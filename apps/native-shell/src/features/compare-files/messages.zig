//! Messages for feature.compare-files.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
