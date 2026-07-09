//! Messages for feature.profiles.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
