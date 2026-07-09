//! Messages for feature.webviews.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
