//! Messages for feature.bracket-matching.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
