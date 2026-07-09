//! Messages for feature.disable-heavy-features.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
