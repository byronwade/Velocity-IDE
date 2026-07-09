//! Messages for feature.themes.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
