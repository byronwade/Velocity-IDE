//! Messages for feature.settings.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
